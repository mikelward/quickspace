// Command quickspace-grant records a quickspace focus grant for a shell
// command line (SPEC.md §14.3), so the first window the command opens may
// take focus.
//
// Every interactive shell calls it before running a command, in a
// quickspace session only:
//
//	quickspace-grant --pid SHELL-PID -- COMMAND-LINE
//
// The grant names the shell's pid, so a window from any process the command
// starts can use it: the focus guard walks the window's parents in /proc.
// It also names the app the line's first command runs, for an app that's
// already running, which opens its window from the process it already had
// (`firefox URL`). That name comes from parsing the line as bash with
// mvdan.cc/sh, past assignments, redirections, `!` and wrappers such as env
// and nohup, with words expanded from this process's environment. A command
// substitution is never run: a program word that needs one names nothing.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"mvdan.cc/sh/v3/expand"
	"mvdan.cc/sh/v3/syntax"
)

func main() {
	os.Exit(run(os.Args[1:], os.Environ(), os.Stderr))
}

func run(args []string, env []string, stderr io.Writer) int {
	flags := flag.NewFlagSet("quickspace-grant", flag.ContinueOnError)
	flags.SetOutput(stderr)
	pid := flags.Int("pid", os.Getppid(), "the `pid` of the shell running the command")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() != 1 {
		fmt.Fprintln(stderr, "usage: quickspace-grant [--pid PID] [--] COMMAND-LINE")
		return 2
	}
	if !inQuickspace(lookup(env, "XDG_CURRENT_DESKTOP")) {
		return 0
	}
	app := program(flags.Arg(0), env)
	if err := grant(app, *pid); err != nil {
		fmt.Fprintf(stderr, "quickspace: couldn't record a focus grant for %s: %v\n", flags.Arg(0), err)
		return 1
	}
	return 0
}

func inQuickspace(desktops string) bool {
	for _, d := range strings.Split(desktops, ":") {
		if d == "quickspace" {
			return true
		}
	}
	return false
}

func lookup(env []string, name string) string {
	for i := len(env) - 1; i >= 0; i-- {
		if value, ok := strings.CutPrefix(env[i], name+"="); ok {
			return value
		}
	}
	return ""
}

// program returns the app id (the program's basename) of the line's first
// command, or "" where it names none: a builtin, a program word only the
// shell could expand, or a line whose first command isn't a simple one
// (fish's `if true; firefox; end`). Later commands on the line go without a
// name; the pid covers them, unless their app was already running.
func program(line string, env []string) string {
	call := firstCall(line)
	if call == nil {
		return ""
	}
	cfg := &expand.Config{Env: expand.ListEnviron(env...)}
	// Expand one word at a time and stop once the program is known, so an
	// argument after it that only the shell could expand doesn't matter.
	var fields []string
	for _, word := range call.Args {
		more, err := expand.Fields(cfg, word)
		if err != nil {
			return ""
		}
		fields = append(fields, more...)
		if name, done := fieldsProgram(fields); done {
			app := filepath.Base(name)
			// A quoted "$BROWSER" holding `firefox --new-window` is one
			// word, which names no program, and no window's class has a
			// space.
			if name == "" || app == "." || app == "/" || strings.ContainsAny(app, " \t\n") {
				return ""
			}
			return app
		}
	}
	return ""
}

// firstCall returns the line's first simple command, looking past `!`,
// `time` and the left side of a pipe or `&&`. A line bash rejects
// (fish's `nautilus (pwd)`) is cut where bash stops.
func firstCall(line string) *syntax.CallExpr {
	file := parsePrefix(line)
	if file == nil || len(file.Stmts) == 0 {
		return nil
	}
	cmd := file.Stmts[0].Cmd
	for {
		switch c := cmd.(type) {
		case *syntax.CallExpr:
			if len(c.Args) == 0 {
				return nil // only assignments
			}
			return c
		case *syntax.BinaryCmd:
			cmd = c.X.Cmd
		case *syntax.TimeClause:
			if c.Stmt == nil {
				return nil
			}
			cmd = c.Stmt.Cmd
		default:
			return nil
		}
	}
}

// parsePrefix parses line as bash, or as much of it as comes before bash's
// first error.
func parsePrefix(line string) *syntax.File {
	parser := syntax.NewParser()
	for range 4 {
		file, err := parser.Parse(strings.NewReader(line), "")
		if err == nil {
			return file
		}
		var offset uint
		var parseErr syntax.ParseError
		var langErr syntax.LangError
		switch {
		case errors.As(err, &parseErr):
			offset = parseErr.Pos.Offset()
		case errors.As(err, &langErr):
			offset = langErr.Pos.Offset()
		default:
			return nil
		}
		if offset == 0 {
			// `word (…)` reads as the start of a function definition.
			offset = uint(max(strings.IndexByte(line, '('), 0))
		}
		if offset == 0 || offset >= uint(len(line)) {
			return nil
		}
		line = line[:offset]
	}
	return nil
}

// Commands that run the next word as the program. and, or and not are
// fish's control prefixes (`false; or firefox`), since fish lines are
// parsed as bash too.
var wrappers = map[string]bool{
	"builtin": true, "command": true, "env": true, "exec": true, "nice": true,
	"nocorrect": true, "noglob": true, "nohup": true, "setsid": true, "time": true,
	"and": true, "or": true, "not": true,
}

// Wrapper long options that take the next word as their value.
var valueOptions = map[string]map[string]bool{
	"env":  {"--chdir": true, "--unset": true},
	"nice": {"--adjustment": true},
}

// Wrapper short options that take a value, in the word or the next.
var valueLetters = map[string]string{"env": "CSu", "exec": "a", "nice": "n"}

// The shell's own builtins in bash and zsh, which run in the shell even
// where a file of the same name is on PATH (echo, pwd, test ...).
var builtins = map[string]bool{}

func init() {
	for _, name := range strings.Fields(`
		. : [ alias autoload bg bind bindkey break builtin caller cd chdir
		command compgen complete compopt continue declare dirs disown echo
		emulate enable eval exec exit export false fc fg functions getopts
		hash help history jobs kill let local logout mapfile popd print
		printf pushd pwd read readarray readonly rehash return set setopt
		shift shopt source suspend test times trap true type typeset ulimit
		umask unalias unfunction unset unsetopt wait whence where which zle
		zmodload`) {
		builtins[name] = true
	}
}

// Wrappers after which the program is a separate executable, never a
// builtin: `env echo` runs /usr/bin/echo.
var externalWrappers = map[string]bool{"env": true, "exec": true, "nice": true, "nohup": true, "setsid": true}

// fieldsProgram finds the program in the expanded words of a simple
// command, so far. done is false while the words so far don't settle it.
// A command that runs no program, or whose program the helper can't tell,
// settles on "": a builtin, `command -v NAME` (which only looks NAME up), a
// wrapper's --help or --version, and `env -S STRING`.
func fieldsProgram(fields []string) (name string, done bool) {
	wrapper := ""
	external := false
	found := func(name string) (string, bool) {
		if !external && builtins[name] {
			return "", true
		}
		return name, true
	}
	for i := 0; i < len(fields); i++ {
		field := fields[i]
		if wrapper == "" {
			if !wrappers[field] {
				return found(field)
			}
			wrapper = field
			external = externalWrappers[field]
			continue
		}
		switch {
		case wrappers[field]:
			wrapper = field
			external = external || externalWrappers[field]
		case field == "--help" || field == "--version":
			return "", true
		case wrapper == "command" && strings.HasPrefix(field, "-") && strings.ContainsAny(field[1:], "vV"):
			return "", true
		case wrapper == "env" && (field == "--split-string" || strings.HasPrefix(field, "--split-string=")):
			return "", true
		case wrapper == "env" && strings.Contains(field, "=") && syntax.ValidName(strings.SplitN(field, "=", 2)[0]):
			// env's own NAME=value arguments
		case field == "--":
			if i+1 < len(fields) {
				return found(fields[i+1])
			}
			return "", false
		case valueLetters[wrapper] != "" && strings.HasPrefix(field, "-") && !strings.HasPrefix(field, "--"):
			// Short options, which may be clustered (`env -iC/opt/app`,
			// `exec -cla NAME`). One that takes a value takes the rest of
			// the word, or the next.
			for j := 1; j < len(field); j++ {
				c := field[j]
				if !strings.ContainsRune(valueLetters[wrapper], rune(c)) {
					continue
				}
				if wrapper == "env" && c == 'S' {
					return "", true
				}
				if j+1 == len(field) {
					i++
				}
				break
			}
		case strings.HasPrefix(field, "-"):
			if valueOptions[wrapper][field] {
				i++
			}
		default:
			return found(field)
		}
	}
	return "", false
}

// grant records a one-shot grant through Hyprland's Lua config, for app's
// windows and those of pid's descendants; with no app, for the descendants
// only.
func grant(app string, pid int) error {
	lua := "nil"
	if app != "" {
		lua = luaString(app)
	}
	out, err := exec.Command("hyprctl", "eval",
		"quickspace_focus.grant("+lua+", "+strconv.Itoa(pid)+")").CombinedOutput()
	reply := strings.TrimSpace(string(out))
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && reply != "" {
			return errors.New(reply)
		}
		return err
	}
	if reply != "ok" {
		return errors.New(reply)
	}
	return nil
}

// luaString quotes s as a Lua string literal.
func luaString(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '"' || c == '\\':
			b.WriteByte('\\')
			b.WriteByte(c)
		case c < 0x20 || c == 0x7f:
			fmt.Fprintf(&b, "\\%03d", c)
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
	return b.String()
}
