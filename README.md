# Package scala-repl.el

## Introduction

This package `scala-repl.el` intends to bring REPL driven development experience to Emacs, for Scala hackers.

It automatically detects the project root by simply searching for `build.sbt` or `build.sc` files in the current folder and its ancestors, till the root folder. When nothing is found, it will simply invoke `scala-cli`. The command to run when a project is (not) found is configurable.

## Usage

### Installation

To use this package, simply put it under your load path and run:

```emacs-lisp
(require 'scala-repl)
```

Enable the minor mode for your convenience:

```emacs-lisp
(scala-repl-mode)
```

You may also bind the following commands by yourself without using the minor mode.

### Default Keymap

| Key Binding | Command                        |
|-------------|--------------------------------|
| C-c C-z     | scala-repl-run                 |
| C-c C-x     | scala-repl-restart             |
| C-c C-a     | scala-repl-attach              |
| C-c C-d     | scala-repl-detach              |
| C-c C-c     | scala-repl-eval-region-or-line |
| C-c C-b     | scala-repl-eval-buffer         |
| C-c C-r     | scala-repl-eval-region         |
| C-c C-o     | scala-repl-clear-output        |

### Key Functions

- `scala-repl-run` fires an REPL and attach to it in an automatic way.
- `scala-repl-run-custom` simply runs an REPL with custom commands. The REPL will *not* be attached automatically.
- `scala-repl-restart` restarts the attached REPL process.
- `scala-repl-attach` sets some buffer-local variables to attach the "current" buffer to an REPL. You only need it when you are manually starting an REPL.
- `scala-repl-detach` as you can guess from its name.
- `scala-repl-clear-output` cleans the content of attached REPL buffer.
- `scala-repl-eval-buffer`, `scala-repl-eval-region-or-line`, `scala-repl-eval-region` and `scala-repl-eval-current-line` are used to evaluate your code.

## Customization 

- `scala-repl-command-alist` can be used to define the mappings between project type (`sbt`, `mill` or `NIL`) and corresponding commands to invoke. Each argument of the command is one element in the list. By default it is set to:

```emacs-lisp
'((mill "mill" "-i" "_.console")
  (sbt "sbt" "console")
  (nil "scala-cli" "repl" "-deprecation"))
```

- `scala-repl-buffer-basename` specifies the default "base" name for REPL buffer. You probably do not need/want to change it, although you are free to mess with it and see what changes.
