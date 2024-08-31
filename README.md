# geiser-overlay

*Absolutely borked for now. May or may not be fixxed*

<!--
[![MELPA](https://melpa.org/packages/geiser-overlay-badge.svg)](https://melpa.org/#/geiser-overlay)
[![MELPA Stable](https://stable.melpa.org/packages/geiser-overlay-badge.svg)](https://stable.melpa.org/#/geiser-overlay)
-->

Overlay Scheme evaluation results.
This is mostly a s/sly-/geiser-/g of sly-overlay.
Sly-overlay borrows from EROS, which borrows from CIDER.

The primary function to call is `geiser-overlay-eval-defun`, which can be bound to
whatever is usually bound to `geiser-eval-defun`.

There is otherwise no other special setup necessary for using the library.

### Installation

`geiser-overlay` is not yet available on MELPA.

[*Working on it*](https://github.com/melpa/melpa/pull/9148)

### Contributing

Please someone help me move to an async geiser eval call.