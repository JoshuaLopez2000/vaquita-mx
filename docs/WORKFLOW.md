# Delivery workflow

The GitHub Project [Vaquita MX — Product Delivery](https://github.com/users/JoshuaLopez2000/projects/1)
is the operational source of truth. Product documentation explains intent and
architecture; project issues track executable work and current status.

## Status flow

```text
Inbox -> Ready -> In Progress -> In review -> Validating -> Done
```

- **Inbox:** captured but not yet prioritized.
- **Ready:** prioritized, clear, sized, and independently testable.
- **In Progress:** implementation has started. Keep at most one major item here
  per developer.
- **In review:** implementation and author verification are complete.
- **Validating:** review passed; acceptance criteria are being verified in a
  realistic environment.
- **Done:** acceptance criteria pass and the change is merged or intentionally
  closed.

GitHub automatically places new project items in Inbox, linked pull requests in
In Progress, approved pull requests in Validating, requested changes in In
Progress, reopened work in Ready, and merged or closed items in Done.

## Project fields

- **Priority:** P0 Critical, P1 High, P2 Normal, or P3 Low.
- **Size:** S Small, M Medium, or L Large. Split an item before starting if it
  cannot remain one reviewable concern.
- **Work type:** Outcome, Feature, Bug, Risk, or Chore.
- **Area:** Product, Mobile, API, Payments, or Infrastructure.
- **Release:** 0.1 Private beta, 0.2 Next, or Later.
- **Target date:** use only for a real delivery commitment or milestone.

## Ready criteria

An item may enter Ready when:

- the problem and expected outcome are clear;
- acceptance criteria are observable and independently testable;
- non-goals and important constraints are recorded;
- dependencies and blockers are known;
- the item is small enough for one focused pull request; and
- verification and rollout expectations are understood.

## Pull request flow

1. Select the highest-priority unblocked Ready item for the active release.
2. Assign it, move it to In Progress, and create a short-lived branch.
3. Implement only the defined scope and add relevant tests.
4. Open a pull request that links the issue and records verification evidence.
5. Address review feedback; requested changes return the item to In Progress.
6. After approval, validate the acceptance criteria in staging or the closest
   realistic environment.
7. Merge only when required checks and acceptance criteria pass.

## Definition of done

- Acceptance criteria are satisfied with evidence.
- Relevant Go and Flutter checks pass.
- Important success and failure paths have tests.
- Offline and remote paths behave consistently; sync, retry, and merge rules
  are preserved.
- Security, privacy, money, migration, and idempotency risks are addressed.
- Documentation and API contracts reflect behavior changes.
- Deployment, monitoring, and rollback are understood.
- The linked pull request is merged and the project item is Done.

## Choosing the next item

Prefer the smallest vertical slice that proves a user outcome or reduces the
largest product, security, or delivery risk. Use this as a tie-breaker:

```text
(user value + risk reduction + learning value) / effort
```

Score value, risk reduction, and learning from 1 to 5. Use 1, 2, 3, 5, or 8
for effort. Security, data-loss, and legal requirements are release gates, not
ordinary backlog tradeoffs.
