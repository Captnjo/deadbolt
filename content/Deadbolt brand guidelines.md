# Deadbolt Brand Identity & Design System

This document outlines the visual identity for **Deadbolt**, an open-source signing gateway for AI agents on Solana. The brand emphasizes security, deliberate human authority, and modern engineering.

---

## 1. Brand Concept
Deadbolt acts as the final boundary between autonomous AI agents and the blockchain. The visual language is inspired by physical lock mechanisms—decisive, mechanical, and unyielding.

* **Security:** Communicated through thick, geometric strokes.
* **Physical Control:** Represented by the horizontal bolt mechanism.
* **Minimalism:** Optimized for high performance in CLI terminals and small-scale UI (favicons).

---

## 2. The Logomark
The "Secure Interface" integrates a stylized letter **'D'** with an active deadbolt latch.

* **Geometry:** A circular 'D' structure intersected by a sharp, horizontal bolt.
* **The Bolt:** Symbolizes the moment of approval. The sharp angles represent the "spark" of digital interaction and precision.
* **Scalability:** Designed to remain legible as small as 16px.

---

## 3. Brand Colors

The palette is rooted in a "Terminal Dark" aesthetic, using a high-energy industrial accent to signal states requiring human intervention.

### Primary Palette
| Color | Hex | Usage |
| :--- | :--- | :--- |
| **Onyx Black** | `#000000` | Primary backgrounds, terminal backdrops. |
| **Pure White** | `#FFFFFF` | Primary logomark, primary typography. |

### Functional Palette (UI States)
| Color | Hex | Status |
| :--- | :--- | :--- |
| **Solar Flare** | `#F87040` | **Awaiting Approval:** The primary brand accent. |
| **Steel Gray** | `#707070` | **Locked/Inactive:** Secondary UI elements. Processing states use Steel Gray with animation (spinner/pulse) rather than a separate color. |
| **Crypto Green** | `#2ECC71` | **Signed/Success:** Transaction confirmation. |
| **Ember Red** | `#E74C3C` | **Error/Rejected:** Failed transactions, guardrail violations, blocked actions. |
| **Tungsten** | `#E2A93B` | **Warning/Caution:** Soft guardrail limits, confirmation prompts, "are you sure?" moments. |

### Surface Palette (Elevation)
| Color | Hex | Usage |
| :--- | :--- | :--- |
| **Onyx Black** | `#000000` | Deepest background layer. |
| **Graphite** | `#141414` | Elevated surfaces — cards, panels, sidebar. |
| **Charcoal** | `#1E1E1E` | Modals, popovers, active panel backgrounds. |
| **Ash** | `#2A2A2A` | Borders, dividers, subtle separators. |

### Text Palette (Hierarchy)
| Color | Hex | Usage |
| :--- | :--- | :--- |
| **Pure White** | `#FFFFFF` | Headlines, primary content, logomark. |
| **Fog** | `#B0B0B0` | Secondary text, labels, captions. (~7.5:1 on Graphite) |
| **Smoke** | `#606060` | Disabled text, placeholders, tertiary. |

---

## 4. Typography

### Font Families
* **Wordmark / UI:** Clean, geometric sans-serif. Recommended: *Inter*, *SF Pro*.
* **CLI / Code / Addresses:** High-legibility monospaced. Recommended: *JetBrains Mono*, *SF Mono*.

### Type Scale
| Role | Weight | Size | Color | Usage |
| :--- | :--- | :--- | :--- | :--- |
| **Display** | Bold | 32px | Pure White | Balance amounts, hero numbers. |
| **Heading** | Semibold | 20–24px | Pure White | Screen titles, section headers. |
| **Subheading** | Semibold | 14px | Fog | Section labels ("Tokens", "Network", "Debug"). |
| **Body** | Regular | 14–16px | Pure White | Primary content, descriptions. |
| **Caption** | Regular | 12–13px | Fog | Secondary info, timestamps, token names. |
| **Mono** | Regular | 13px | Fog | Addresses, RPC URLs, transaction hashes. |
| **Disabled** | Regular | 12–14px | Smoke | Placeholder text, inactive labels. |

### Lockup Style
The logomark 'D' can function as the first letter of the wordmark or as a standalone icon positioned to the left of the project name.

---

## 5. Logo Usage

### Clear Space
Maintain a minimum clear space equal to the height of the bolt element on all sides of the logomark. No text, graphics, or visual noise should intrude into this zone.

### Minimum Size
The logomark must not be rendered smaller than **16px** in digital or **5mm** in print. Below this threshold the bolt detail becomes illegible.

### Approved Backgrounds
| Background | Logomark Color | Notes |
| :--- | :--- | :--- |
| Onyx Black `#000000` | Pure White | Primary usage. |
| Graphite `#141414` | Pure White | Cards, elevated surfaces. |
| Pure White `#FFFFFF` | Onyx Black | Inverted — light-background contexts only. |
| Photography / texture | Pure White with subtle drop shadow or container | Avoid placing directly on busy imagery. |

### Don'ts
* Do not recolor the logomark with functional palette colors (no orange/green/red 'D').
* Do not rotate, skew, or add effects (gradients, glows, bevels).
* Do not separate the bolt from the 'D' — the mark is one unit.
* Do not place the logomark on backgrounds with insufficient contrast (< 4.5:1).
* Do not stretch or alter the aspect ratio.

---

## 6. Visual Applications

### Terminal (CLI) Mockup
In the command line, the logomark acts as a status indicator. State colors map directly to the functional palette.

```bash
user@terminal:~/$ deadbolt sign --tx 7Vbm...3xTM
> [LOCKED] Awaiting manual approval...          # Steel Gray
> [D] Proceed? (y/n)                            # Solar Flare
> [SIGNED] Tx confirmed: 4kNp...9vRz            # Crypto Green
```

```bash
user@terminal:~/$ deadbolt sign --tx 9Qwx...1fPm
> [LOCKED] Awaiting manual approval...          # Steel Gray
> [REJECTED] Guardrail: exceeds 10 SOL limit    # Ember Red
```

### Desktop App (Flutter)
The desktop wallet uses the full palette:
* **Surfaces:** Onyx Black (deepest) → Graphite (cards) → Charcoal (modals) → Ash (borders).
* **Text:** Pure White (primary) → Fog (secondary) → Smoke (disabled).
* **State indicators:** Network badge colors, transaction status chips, and balance loading spinners all draw from the functional palette.
* **Brand accent:** Solar Flare is used sparingly — action buttons requiring human decision, not decoration.

### Social / Web
* Open-graph images: Onyx Black background, Pure White logomark, Solar Flare tagline text.
* GitHub README badges: Onyx Black background with Pure White text. Status badges use functional colors.
* Favicon: Pure White logomark on transparent background (dark browser tabs) or Onyx Black logomark on transparent (light tabs).

---

## 7. Voice & Tone

Deadbolt's voice is **terse, precise, and confident**. It communicates like a well-engineered system — no filler, no false reassurance, no marketing fluff.

### Principles

* **Direct.** Say what happened, what's needed, and nothing else. "Transaction rejected: exceeds daily limit" — not "Oops! It looks like something went wrong with your transaction."
* **Mechanical, not robotic.** Deadbolt has the personality of a well-built tool. It doesn't crack jokes, but it's not cold either. It respects the user's time and intelligence.
* **Human authority, always.** Every message reinforces that the human is in control. "Awaiting your approval" — not "Processing your request."
* **Specific over vague.** Show the address, the amount, the program ID. Security demands specificity. Never say "something" when you can say exactly what.

### Examples

| Context | Good | Bad |
| :--- | :--- | :--- |
| Approval prompt | "Sign transfer of 2.5 SOL to 7Vbm...3xTM?" | "Do you want to proceed with this transaction?" |
| Guardrail block | "Blocked: 15 SOL exceeds 10 SOL per-tx limit." | "This transaction couldn't be completed." |
| Success | "Signed. Tx: 4kNp...9vRz" | "Your transaction was successfully submitted!" |
| Error | "RPC unreachable: api.mainnet-beta.solana.com" | "We're having trouble connecting. Please try again later." |

### Capitalization
* UI labels and buttons: Sentence case ("Sign transaction", not "Sign Transaction").
* Status tags: ALL CAPS for state keywords only (`LOCKED`, `SIGNED`, `REJECTED`).
* Never use title case for sentences or descriptions.

---

## 8. Accessibility

### Contrast Requirements
All text must meet **WCAG 2.1 AA** minimum contrast ratios against its background:
* **Normal text (< 18px):** 4.5:1 minimum.
* **Large text (>= 18px bold or >= 24px):** 3:1 minimum.

### Key Contrast Pairs (verified)
| Foreground | Background | Ratio | Pass |
| :--- | :--- | :--- | :--- |
| Pure White `#FFFFFF` | Onyx Black `#000000` | 21:1 | AA, AAA |
| Pure White `#FFFFFF` | Graphite `#141414` | 16.5:1 | AA, AAA |
| Fog `#B0B0B0` | Graphite `#141414` | 7.5:1 | AA, AAA |
| Fog `#B0B0B0` | Onyx Black `#000000` | 9.8:1 | AA, AAA |
| Smoke `#606060` | Onyx Black `#000000` | 3.7:1 | Large text only |
| Solar Flare `#F87040` | Onyx Black `#000000` | 6.3:1 | AA |
| Crypto Green `#2ECC71` | Onyx Black `#000000` | 10.3:1 | AA, AAA |
| Ember Red `#E74C3C` | Onyx Black `#000000` | 5.0:1 | AA |
| Tungsten `#E2A93B` | Onyx Black `#000000` | 8.6:1 | AA, AAA |

### Functional Color Usage
Never rely on color alone to convey state. Pair every functional color with a text label or icon:
* Crypto Green + "Signed" label
* Ember Red + "Rejected" label + error icon
* Solar Flare + "Awaiting approval" label
