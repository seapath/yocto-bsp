# CI/CD documentation

The red stroked boxes are the workflows that can potentially run in the context of an external contributor's PR. Those workflows are ran unprivileged: no secrets, read-only token (see https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflows-in-forked-repositories).

```mermaid
flowchart TD
    classDef unprivileged stroke:red,stroke-dasharray:5;

   subgraph yocto-bsp
        push-bsp[push.yml]
        pr-bsp[pr.yml]:::unprivileged

        pr-summary.yml
        periodic-cve-check.yml
        _cve-check.yml
        _build.yml

        pr-bsp ==> _build.yml
        pr-bsp ==> _cve-check.yml
        pr-bsp -.->|workflow_run| pr-summary.yml

        periodic-cve-check.yml ==> _cve-check.yml

        push-bsp ==> _build.yml
        push-bsp -.->|workflow_run| periodic-cve-check.yml

   end

   subgraph meta-seapath
        push-meta[push.yml] -->|workflow_dispatch| push-bsp

        pr-meta[pr.yml]:::unprivileged
        pr-deleg-meta[pr-delegation.yml]

        pr-meta -.->|workflow_run| pr-deleg-meta
        pr-deleg-meta -->|workflow_dispatch| pr-bsp
   end
```
