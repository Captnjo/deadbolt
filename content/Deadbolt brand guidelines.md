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
| **Steel Gray** | `#707070` | **Locked/Inactive:** Secondary UI elements. |
| **Crypto Green** | `#2ECC71` | **Signed/Success:** Transaction confirmation. |

---

## 4. Typography

* **Wordmark:** Clean, geometric sans-serif (Recommended: *Inter*, *Roboto*, or *SF Pro*).
* **CLI / Code:** High-legibility monospaced fonts (Recommended: *JetBrains Mono*, *SF Mono*).
* **Lockup Style:** The logomark 'D' can function as the first letter of the wordmark or as a standalone icon positioned to the left of the project name.

---

## 5. Visual Applications

### Terminal (CLI) Mockup
In the command line, the logomark acts as a status indicator:

```bash
user@terminal:~/$ deadbolt sign --tx [0x123...]
> [LOCKED] Awaiting manual approval...
> [D] Proceed? (y/n)
