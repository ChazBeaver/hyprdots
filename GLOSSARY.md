# Hyprdots language

Vocabulary for the personal desktop layer and its theme lifecycle. Commands
and file layout are documented in the README and the theme skill.

## Ownership and convergence

**Desired state**: The configuration and source revisions declared by the
owning repository, including which components it is responsible for keeping.

**Installed state**: The configuration, links, and source checkouts currently
present on a particular machine.

**Managed component**: A component whose desired state is declared and
maintained by an owning repository. Being installed alone does not make a
component managed.

**Convergence**: Bringing installed state into agreement with declared desired
state. A missing managed component remains desired until that declaration changes.

**Drift**: A difference between declared desired state and observed installed
state. A missing component alone does not establish an intentional removal.

## Themes

**Theme slug**: The stable name identifying a theme across installation and
persistence records.

**Theme pin**: The declaration that a theme is managed at a specific source
repository, revision, and location within that repository. A pin is distinct
from an installed copy.

**Theme source**: A repository supplying the contents of one or more themes.

**Community theme**: A theme installed from its own upstream repository,
treated as third-party content by Omarchy.

**Vault theme**: A personally authored theme maintained within the shared
private theme vault. Removing its local installation does not delete the
authored source from the vault.

**Stock theme**: A theme supplied and owned by the Omarchy package, rather
than by the personal theme lock.

**Unpinning**: Releasing a theme from persistence management while retaining
its installed copy.

**Uninstalling**: Removing a theme's local installation. Coordinated removal
also withdraws its pin, so convergence no longer restores the installation.

**Recorded prior removal**: An intentional uninstall already completed on
the machine whose remaining persistence declaration is being withdrawn.
