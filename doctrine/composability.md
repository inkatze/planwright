# Composability by Default

At the domain and logic layer, prefer small units that take data in and
return data out. Compose them through the language's natural mechanism
(pipes, chaining, function composition, middleware stacks) rather than
coordinating through shared mutable state or deep inheritance.

At the framework boundary (routing, configuration, ORM, dependency
injection), follow the framework's established conventions: a controller, a
route handler, a context module should look like what someone familiar with
that stack expects. Idiomatic at the boundary, composable inside it.

**The test:** could this unit be used in a different context without
importing its neighbors?

Do not reach for service abstractions, domain-driven-design aggregates, or
architectural patterns unless the problem genuinely requires coordination
beyond what function composition provides. Abstractions are added when a
real requirement demands them, not in anticipation of one (the same rule
Refactor Instinct applies to review findings).

Citations: REQ-D2.1.

## Reflexively: planwright's own architecture

The principle governs planwright itself, not only the code it helps adopters
write. Knowledge lives in doctrine docs (data), behavior lives in skills
(functions over that data), enforcement lives in hooks (the framework
boundary). Skills compose in-session, as function calls, not as separate
processes. A doctrine doc is useful to a skill that did not ship with it;
that is the same could-it-move-contexts test applied to the framework's own
units.
