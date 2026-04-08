const { setGlobalOptions } = require("firebase-functions");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

setGlobalOptions({ region: "us-central1" });

// ─── Helper: send FCM to a single token ─────────────────────────────────────

/**
 * Sends a Firebase Cloud Messaging notification to a single device token.
 * @param {string} token - The FCM device token.
 * @param {string} title - Notification title.
 * @param {string} body - Notification body text.
 * @param {Object} data - Optional key-value data payload.
 * @return {Promise<boolean>} True if sent successfully, false otherwise.
 */
async function sendFcm(token, title, body, data = {}) {
  const message = {
    notification: { title, body },
    data: { ...data, click_action: "FLUTTER_NOTIFICATION_CLICK" },
    android: {
      priority: "high",
      notification: {
        sound: "default",
        channelId: "fcm_channel",
      },
    },
    token,
  };

  try {
    await admin.messaging().send(message);
    console.log(`✅ FCM sent → token ending …${token.slice(-8)}`);
    return true;
  } catch (err) {
    console.error(`❌ FCM failed → ${err.message}`);
    return false;
  }
}

// ─── Helper: small delay to avoid rate limits ────────────────────────────────

/**
 * Returns a promise that resolves after the given number of milliseconds.
 * @param {number} ms - Milliseconds to wait.
 * @return {Promise<void>}
 */
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ═══════════════════════════════════════════════════════════════════════════════
// 1. sendBillReminder — called by the Flutter app after email parsing
// ═══════════════════════════════════════════════════════════════════════════════

exports.sendBillReminder = onRequest(async (req, res) => {
  try {
    const db = admin.firestore();

    const amount = req.body.amount || "0";
    const dueDate = req.body.dueDate || "N/A";
    const bank = req.body.bank || "Bank";

    console.log("📩 Incoming bill reminder request:", { amount, dueDate, bank });

    const usersSnapshot = await db.collection("users").get();

    if (usersSnapshot.empty) {
      return res.status(200).send("No users found");
    }

    let sentCount = 0;
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      const token = data.fcmToken;

      if (!token) {
        console.log(`⏭️ No FCM token for user ${doc.id}`);
        continue;
      }

      const title = `💳 ${bank} Bill Due`;
      const body = `Your bill of ₹${amount} is due on ${dueDate}.`;
      const sent = await sendFcm(token, title, body, { bank, amount, dueDate });
      if (sent) sentCount++;

      // Small delay to avoid quota issues
      await delay(100);
    }

    res.status(200).json({ success: true, sent: sentCount });
  } catch (error) {
    console.error("🔥 sendBillReminder error:", error);
    res.status(500).json({ error: error.message });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// 2. dailyBillChecker — runs every day at 9 AM UTC (2:30 PM IST)
//    Scans all users' cards in Firestore and sends reminders for upcoming bills
// ═══════════════════════════════════════════════════════════════════════════════

exports.dailyBillChecker = onSchedule("0 9 * * *", async () => {
  console.log("⏰ Daily bill checker started at", new Date().toISOString());

  const db = admin.firestore();
  const now = new Date();

  // Check bills due in 0, 1, or 3 days from now (T-day, T-1, T-3)
  const warningThresholds = [0, 1, 3];

  try {
    const usersSnapshot = await db.collection("users").get();
    console.log(`👥 Checking ${usersSnapshot.size} user(s)...`);

    for (const userDoc of usersSnapshot.docs) {
      const uid = userDoc.id;
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;

      if (!fcmToken) {
        console.log(`⏭️ Skipping user ${uid} — no FCM token`);
        continue;
      }

      // Read this user's cards from Firestore backup
      let cardsSnapshot;
      try {
        cardsSnapshot = await db
          .collection("users")
          .doc(uid)
          .collection("cards")
          .get();
      } catch (err) {
        console.log(`⚠️ Could not read cards for user ${uid}: ${err.message}`);
        continue;
      }

      if (cardsSnapshot.empty) {
        console.log(`📭 No cards found for user ${uid}`);
        continue;
      }

      for (const cardDoc of cardsSnapshot.docs) {
        const card = cardDoc.data();

        if (!card.due_date || card.is_paid === 1) continue;

        let dueDate;
        try {
          dueDate = new Date(card.due_date);
        } catch (_) {
          continue;
        }

        if (isNaN(dueDate.getTime())) continue;

        // Calculate days until due
        const msPerDay = 1000 * 60 * 60 * 24;
        const daysUntilDue = Math.ceil((dueDate - now) / msPerDay);

        if (!warningThresholds.includes(daysUntilDue)) continue;

        const bank = card.bank || "Your card";
        const spent = card.spent ? `₹${Math.round(card.spent)}` : "outstanding";
        const dueDateStr = dueDate.toLocaleDateString("en-IN", {
          day: "2-digit",
          month: "short",
          year: "numeric",
        });

        let urgency = "";
        if (daysUntilDue === 0) urgency = "❗ DUE TODAY";
        else if (daysUntilDue === 1) urgency = "⚠️ Due TOMORROW";
        else urgency = "📅 Due in 3 days";

        const title = `${bank} Bill Due ${urgency}`;
        const body = `${spent} due on ${dueDateStr}. Pay on time to avoid charges.`;

        await sendFcm(fcmToken, title, body, {
          bank,
          amount: String(card.spent || 0),
          dueDate: card.due_date,
          type: "bill_reminder",
        });

        console.log(`📨 Reminder sent to user ${uid} for ${bank} — ${daysUntilDue} day(s) away`);

        // Delay between notifications to be kind to Firebase quota
        await delay(200);
      }
    }

    console.log("✅ Daily bill checker completed.");
  } catch (error) {
    console.error("🔥 dailyBillChecker error:", error);
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// 3. notifyBillDetected — called when app detects a new bill via email parsing
//    (optional HTTP endpoint for future server-side email processing)
// ═══════════════════════════════════════════════════════════════════════════════

exports.notifyBillDetected = onRequest(async (req, res) => {
  try {
    const { uid, bank, amount, dueDate } = req.body;

    if (!uid || !bank) {
      return res.status(400).json({ error: "uid and bank are required" });
    }

    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(uid).get();

    if (!userDoc.exists) {
      return res.status(404).json({ error: "User not found" });
    }

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) {
      return res.status(200).json({ message: "No FCM token, skipping" });
    }

    const formattedAmount = amount ? `₹${Math.round(amount)}` : "A new bill";
    const dueDateStr = dueDate || "soon";

    const title = `💳 ${bank} Bill Detected`;
    const body = `${formattedAmount} is due on ${dueDateStr}.`;

    const sent = await sendFcm(fcmToken, title, body, {
      bank,
      amount: String(amount || 0),
      dueDate: dueDateStr,
      type: "bill_detected",
    });

    res.status(200).json({ success: sent });
  } catch (error) {
    console.error("🔥 notifyBillDetected error:", error);
    res.status(500).json({ error: error.message });
  }
});
