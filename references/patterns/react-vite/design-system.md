# Design System — DaisyUI + Datadog Theme

This frontend uses **DaisyUI v5** on **Tailwind v4**. Use DaisyUI semantic classes for all UI — avoid hand-rolled CSS for anything DaisyUI covers.

---

## Palette & Rebranding

**Single file to change:** `src/theme.css`

To rebrand for a customer, ask the AI:
> "Update `src/theme.css` to use `#XXXXXX` as the primary color and `#YYYYYY` as the secondary color."

Three variables drive the entire brand:
- `--color-primary` — navbar, primary buttons, user chat bubbles
- `--color-secondary` — secondary buttons, accents
- `--color-accent` — mirrors `--color-primary` by default; update alongside primary when rebranding

All DaisyUI components cascade automatically via CSS custom properties.

---

## Component Class Reference

### Layout
| Class | Use |
|---|---|
| `navbar` | Top navigation bar wrapper |
| `navbar-start` / `navbar-end` / `navbar-center` | Navbar sections |
| `menu menu-horizontal` | Horizontal nav links inside navbar |
| `drawer` | Side-drawer layout |

### Surface
| Class | Use |
|---|---|
| `card` | Content card container |
| `card-body` | Padding + flex column inside a card |
| `card-title` | Bold heading inside card-body |
| `stat` | Single metric block |
| `stat-title` / `stat-value` / `stat-desc` | Stat block sections |

### Data
| Class | Use |
|---|---|
| `table` | Data table |
| `table-xs` / `table-sm` | Compact table variants |
| `badge` | Inline status pill |
| `badge-success` / `badge-warning` / `badge-error` / `badge-info` | Semantic badge colors |
| `badge-ghost` / `badge-outline` | Neutral badge variants |

### Forms
| Class | Use |
|---|---|
| `input input-bordered` | Text input |
| `input-sm` / `input-xs` | Compact input sizes |
| `select select-bordered` | Dropdown |
| `textarea textarea-bordered` | Multiline textarea |
| `form-control` | Wrapper that spaces label + input |
| `label` / `label-text` | Form label |

### Actions
| Class | Use |
|---|---|
| `btn btn-primary` | Primary action |
| `btn btn-ghost` | Transparent/text button |
| `btn btn-outline` | Outlined button |
| `btn-sm` / `btn-xs` | Compact button sizes |
| `btn-circle` | Circular icon button |

### Feedback
| Class | Use |
|---|---|
| `alert` | Status/information banner |
| `alert-success` / `alert-error` / `alert-warning` / `alert-info` | Semantic alert variants |
| `loading loading-spinner` | Spinner |
| `progress` | Progress bar |

### Chat
| Class | Use |
|---|---|
| `chat chat-start` | Assistant message row (left) |
| `chat chat-end` | User message row (right) |
| `chat-bubble` | Message bubble |
| `chat-bubble-primary` | User bubble in primary color |
| `chat-image` | Avatar slot inside a chat row |

---

## Contrast Conventions

| Background | Required text class |
|---|---|
| `bg-base-100` (white) | Add `text-base-content` explicitly |
| `bg-base-200` / `bg-base-300` | Inherits `text-base-content` via theme |
| `bg-primary` | `text-primary-content` (auto via DaisyUI) |
| `badge-success` / `badge-error` / `badge-info` (badge modifiers) | White text — baked into theme |
| `badge-warning` (badge modifier) | Dark text — baked into theme |

**Rule:** assistant chat bubbles always need `text-base-content`:
```tsx
<div className="chat-bubble bg-base-100 text-base-content">…</div>
```
