# New-machine installation plan moved to Setupdots

The cross-repository plan now lives in
[Setupdots](../../../setupdots/docs/plans/new-machine-install.md).
Its [ownership ADR](../../../setupdots/docs/adr/0001-coordinate-repository-installation.md)
records the accepted decision to keep new-machine coordination separate from
Hyprdots' desktop responsibilities.

Clone `git@github.com:ChazBeaver/setupdots.git` alongside Hyprdots under
`~/Projects/home` if that checkout is not present. The canonical plan carries
forward the rebuild requirements, open font/appearance decisions, and future
verification work. No installer or desktop behavior was changed by moving it.
