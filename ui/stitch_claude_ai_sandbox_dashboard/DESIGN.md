```markdown
# Design System Specification: The Technical Monolith

## 1. Overview & Creative North Star
The creative North Star for this design system is **"The Technical Monolith."** 

This isn't a standard "SaaS dashboard"; it is a high-performance instrument for developers. We are moving away from the "boxy" nature of traditional cloud consoles toward an editorial-grade technical interface. By combining the precision of monospaced data with the fluidity of layered dark surfaces, we create an environment that feels both industrial and premium. 

To break the "template" look, we utilize **Intentional Asymmetry**. Key metrics shouldn't always sit in a perfect grid; use overlapping containers and varying vertical rhythms to guide the eye. We favor **Tonal Depth** over structural lines, making the interface feel like a single, cohesive piece of carved obsidian rather than a collection of disparate widgets.

---

## 2. Colors: The Depth of Charcoal
The palette is rooted in `surface` (#131313), using a spectrum of cool grays and vibrant technical accents to define hierarchy.

### The "No-Line" Rule
**Explicit Instruction:** Prohibit 1px solid borders for sectioning. We do not "box in" content. Boundaries must be defined solely through background color shifts. For example, a `surface-container-low` code block should sit directly on a `surface` background. The change in tone is the border.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. Each level of nesting moves "closer" to the user:
*   **Base Level:** `surface` (#131313) – The infinite void.
*   **Sectioning:** `surface-container-low` (#1C1B1B) – Used for primary content areas.
*   **Interactions:** `surface-container-high` (#2A2A2A) – Used for hover states or active card elements.
*   **Floating Elements:** `surface-container-highest` (#353534) – Used for modals and popovers.

### The "Glass & Gradient" Rule
To inject "soul" into the technical aesthetic:
*   **Glassmorphism:** Use `surface-variant` at 60% opacity with a `20px` backdrop-blur for floating sidebars or command palettes.
*   **Signature Textures:** Main CTAs should never be flat. Use a subtle linear gradient from `primary` (#ADC6FF) to `primary-container` (#4D8EFF) at a 135-degree angle to create a "light-source" effect.

---

## 3. Typography: The Editorial Engineer
We utilize a dual-font strategy to balance human readability with machine precision.

*   **The Voice (Sans):** We use **Inter** for UI elements, navigation, and titles. It is objective and neutral.
*   **The Data (Mono):** We use **Space Grotesk** (specifically for labels) and **JetBrains Mono** (for code/metrics) to signal "technical authority."

**Typography Levels:**
*   **Display/Headline:** High-contrast Inter. Use `headline-lg` (2rem) for page titles to establish an editorial feel.
*   **Title/Body:** Use `title-md` for card headers. `body-md` is our workhorse for descriptions.
*   **Labels:** Use `label-md` (Space Grotesk) in all-caps with 0.05em letter spacing for metadata and status tags. This creates a "blueprint" aesthetic.

---

## 4. Elevation & Depth
In this design system, shadows are light, and borders are ghosts.

*   **The Layering Principle:** Stack `surface-container-lowest` (#0E0E0E) cards on a `surface-container-low` background to create a "recessed" look, or vice-versa for a "lifted" look. 
*   **Ambient Shadows:** For floating elements (Modals/Dropdowns), use a 40px blur with 8% opacity. The shadow color should be `surface-container-lowest` to feel like an ambient occlusion rather than a dark glow.
*   **The "Ghost Border" Fallback:** If a container requires a boundary (e.g., in high-density data tables), use a **Ghost Border**: `outline-variant` (#424754) at 15% opacity. It should be felt, not seen.

---

## 5. Components

### Buttons
*   **Primary:** Gradient fill (`primary` to `primary-container`). `md` (0.375rem) rounded corners. Text is `on-primary`.
*   **Secondary:** Ghost style. No fill, `outline-variant` border at 20% opacity.
*   **Tertiary:** Text only using `primary` color, shifting to `surface-container-high` on hover.

### Status Chips
*   **Active/Success:** `secondary-container` (#00A572) background with `secondary` (#4EDEA3) text.
*   **Warning/Error:** `error-container` (#93000A) background with `error` (#FFB4AB) text.
*   **Styling:** No borders. Use `label-sm` (Space Grotesk) for the typeface.

### Input Fields
*   **Structure:** `surface-container-lowest` background. 
*   **State:** On focus, the background remains dark, but the "Ghost Border" opacity increases to 100% using the `primary` color.
*   **Monospace Input:** All technical inputs (IP addresses, CRON jobs, IDs) must use `JetBrains Mono`.

### Cards & Lists
*   **Rule:** Forbid divider lines.
*   **Alternative:** Use 24px of vertical white space to separate list items. For cards, use a subtle shift from `surface` to `surface-container-low`.

### Technical "Pulse" (New Component)
*   **Definition:** A small, animated 4px dot using `secondary` (mint) placed next to "Live" server metrics. It utilizes a `2px` outer glow of the same color at 30% opacity to simulate a real hardware LED.

---

## 6. Do's and Don'ts

### Do
*   **Do** use asymmetrical layouts. A 3-column grid where the center column is wider feels more intentional than three equal blocks.
*   **Do** lean into high-contrast type scales. A very large `display-md` title next to a very small `label-sm` metadata tag creates "Visual Drama."
*   **Do** use `backdrop-blur` on any element that sits "above" the main content flow.

### Don't
*   **Don't** use 100% white (#FFFFFF) for body text. Use `on-surface-variant` (#C2C6D6) to reduce eye strain and maintain the dark aesthetic.
*   **Don't** use standard "drop shadows." If a card needs to stand out, use a tonal background shift instead.
*   **Don't** use rounded corners larger than `0.5rem` (lg). This system is precision-engineered; overly round corners feel too consumer-soft.

### Accessibility Note
Ensure that all `primary` and `secondary` accents maintain at least a 4.5:1 contrast ratio against the `surface-container` tiers. Use the `primary-fixed-dim` tokens when the standard `primary` lacks sufficient contrast on darker backgrounds.```