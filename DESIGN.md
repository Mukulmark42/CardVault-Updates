# Design System: CardVault
**Project ID:** Local-CardVault

## 1. Visual Theme & Atmosphere
The design philosophy of CardVault embodies a "Premium Glassmorphic" and "Secure" aesthetic. It utilizes a highly polished, modern interface with deep, rich background tones in dark mode, and soft, airy tones in light mode. The atmosphere is sophisticated and high-tech, achieved through the extensive use of frosted glass effects (Backdrop filters with high blur), subtle glowing gradients, and crisp, legible typography. The overall mood conveys trust, elegance, and cutting-edge security.

## 2. Color Palette & Roles
* **Deep Amethyst Purple (#7C3AED):** Used as the primary brand color, often paired with Indigo for vibrant, active gradients on buttons and icons.
* **Vibrant Indigo (#4F46E5):** Used alongside Deep Amethyst to create premium linear gradients for primary actions and highlights.
* **Midnight Slate (#020617):** The core background color for dark mode, providing a deep, immersive canvas.
* **Deep Navy Cosmos (#0D1B3E / #1A1040):** Used as the center of radial gradients in the background to create depth and a subtle glow effect.
* **Frosted Obsidian (#0F172A):** Used for elevated surface elements like bottom sheets, dialogs, and cards in dark mode.
* **Soft Frost Blue (#F0F4FF / #EEF2FF):** The core background gradient colors for light mode, creating a clean and airy feel.
* **Emerald Success (#10B981):** Used for positive actions, such as marking a card as paid.
* **Alert Red (#FF5252):** Used for destructive actions like deleting a card or error messages.

## 3. Typography Rules
* **Font Family:** Poppins (Google Fonts) is used exclusively across the application for a modern, geometric look.
* **Headers:** Extra Bold (Weight 800), large sizing (e.g., 28px), with tight letter-spacing (e.g., -0.5) to create impactful, dense titles (e.g., "Virtual Vault").
* **Subtitles & Labels:** Semi-bold (Weight 600) to Bold (Weight 700), sized around 13-15px, used for card names and list tile titles.
* **Body & Metadata:** Medium (Weight 500) to Regular, sized around 11-12px, often with lower opacity (e.g., white38) for secondary information like card variants or "cards stored securely".
* **Overlines / Section Headers:** Bold (Weight 700), tiny text (10-11px), with wide letter-spacing (1.2) for collection names or section dividers.

## 4. Component Stylings
* **Buttons:** Primary buttons (like the "Add Card" FAB) are square with generously rounded corners (14px). They feature a diagonal Deep Amethyst to Vibrant Indigo gradient and a soft, glowing drop shadow of the same purple hue (14px blur, offset 0,5).
* **Cards/Containers:** Surfaces use strong glassmorphism. Bottom sheets and profile cards use a high blur (sigma 16-24) over a semi-transparent Frosted Obsidian background (0.92 opacity). Corners are very rounded (22px to 28px). Borders are whisper-thin, using white at 8% opacity to catch the light.
* **Inputs/Forms:** Search bars and text fields feature pill-like or generously rounded edges (18px). They use a frosted glass backdrop (blur sigma 10) with a very sheer white fill (5% opacity in dark mode) and delicate 6% opacity borders. Focused states highlight the border in Deep Amethyst (#7C3AED).
* **List Tiles:** Interactive rows feature a subtle background highlight on press. Leading icons are wrapped in softly rounded square containers (10px radius) with a 12% opacity tint of the icon's color.

## 5. Layout Principles
* **Spacing & Margins:** The layout relies on generous, breathable margins. Screen edges typically maintain 20px to 22px of horizontal padding.
* **Grouping & Dividers:** Related items in bottom sheets or settings lists are separated by ultra-thin dividers (1px height, 10% opacity).
* **Rhythm:** Vertical rhythm uses moderate spacing (16px to 28px) between major sections (e.g., between the header, search bar, and card lists) to create a clear visual hierarchy and avoid clutter.
