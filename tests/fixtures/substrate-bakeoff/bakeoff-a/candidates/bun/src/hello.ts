// The harness's trivial program, Bun-compiled TypeScript comparison point:
// `hello <name>` prints "hello <name>" and a newline and exits zero.
process.stdout.write(`hello ${process.argv[2] ?? ""}\n`);
