// The harness's trivial program, Bun-compiled TypeScript comparison point:
// `hello <name>` prints "hello <name>" and a newline and exits zero.
// Typed locally so the plugin validator's type check needs no node types.
declare const process: { argv: string[]; stdout: { write(s: string): unknown } };
process.stdout.write(`hello ${process.argv[2] ?? ""}\n`);
