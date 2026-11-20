# Error budget policy

> **Draft.** Structure follows the SRE Workbook's example policy ([sources](sources.md)).
> It applies only once stakeholders have agreed it (plan item P2.2).

## Why

An SLO's target leaves room for some failure: a 99.5% target allows 0.5% bad events in
the window. That allowance is the error budget. This policy says what a team does when it
spends it.

## Applies to

Every SLO created through sli-catalog with `alerting: live`. SLOs in `observe` are still
being calibrated and are not held to it.

## While the budget lasts

Ship as usual. Spending budget on releases and experiments is what it is for.

## When an SLO has spent its budget for the window

1. The owning team prioritises reliability work for that service over new features until
   the SLO is back within budget over the window.
2. Changes to that service are limited to fixes for the problem, security fixes, and
   urgent business needs that the team lead and Mission Control agree to.
3. If the cause was a dependency the team does not own, the team raises it with the
   owning team instead, and the freeze does not apply.

## When one incident spends a large share

If a single incident spends more than 20% of a window's budget, it gets a postmortem with
at least one action item that would prevent or shorten a repeat.

## When the target is wrong

If the SLO is always met with lots to spare, or always missed while users are not
affected, the target or the SLI is wrong. Fix the slo.yaml rather than ignoring the
budget. Review targets every quarter.

## Disagreements

Escalate to the Head of Mission Control, whose decision stands.
