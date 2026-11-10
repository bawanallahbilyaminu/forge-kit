# Software document outlines

Every document starts with this header block:
```
# <Document title>
| Project | <name> | Version | 0.1 | Date | <date> | Status | Draft |
```
Every document ends with these two sections:
```
## Open questions
## Revision history
```
Write real content for every section. If a section doesn't apply, say why in one line.

## 01-business

**project-brief.md** (1–2 pages): background, problem, objectives (SMART), proposed solution, target users, success criteria, high-level scope, constraints, key assumptions.

**project-charter.md**: purpose and justification, measurable objectives, high-level requirements, summary milestones, summary budget or effort, key stakeholders, sponsor and project manager, authority and approval requirements, high-level risks, exit criteria.

**brd.md** (Business Requirements Document): executive summary, business objectives, current state ("as-is") and future state ("to-be"), business requirements `BR-xx` with priority (MoSCoW), stakeholders and needs, business rules, success metrics and KPIs, cost-benefit summary, assumptions, constraints, dependencies.

**stakeholder-register.md**: a table with columns Stakeholder, Role, Interest, Influence (H/M/L), Needs, Engagement approach.

## 02-product

**prd.md** (Product Requirements Document): vision, goals and non-goals, target personas (summary), problem scenarios, a feature list with priority and release (MVP / v1 / later), user stories (linked to user-stories.md), UX principles, analytics and success metrics, release plan, dependencies.

**personas.md**: 2–4 personas, each with goals, frustrations, context (device, connectivity, language), and a quote.

**user-stories.md**: `US-xx`: As a <persona> I want <goal> so that <benefit>. Each story has acceptance criteria in Given/When/Then form and a priority.

## 03-requirements

**urs.md** (User Requirements Specification): introduction (purpose, scope, definitions), user classes, operating environment from the user's view, and user requirements `UR-xx` written in the user's language ("The user shall be able to…"), each with rationale, priority and source (stakeholder or story).

**srs.md** (System Requirements Specification, IEEE 29148 style):
1. Introduction: purpose, scope, definitions, references, overview.
2. Overall description: product perspective (context diagram in Mermaid), product functions, user classes, operating environment, design and implementation constraints, assumptions and dependencies.
3. External interface requirements: UI, hardware, software (APIs and integrations with their limits), communications.
4. Functional requirements: `FR-xx` grouped by feature. Each has a description, inputs, processing, outputs, errors, priority, and traces-to (`UR-xx`, `US-xx`).
5. Non-functional requirements `NFR-xx`: performance, security, privacy and data protection (NDPA in Nigeria, GDPR where relevant), reliability and availability, usability and accessibility, localisation, maintainability, portability, compliance. Each must be measurable.
6. Data requirements summary (details in data-design.md).
7. Appendices.

**traceability-matrix.md**: a table with columns UR, FR, Design ref (SDD section), Test cases, Status. Add a coverage summary at the end.

## 04-architecture

**sdd.md** (Software Design Document / technical specification): design goals and constraints, architecture overview (Mermaid component diagram), technology stack with reasons (links to ADRs), a section per module (responsibility, interfaces, key classes or functions, error handling), main sequence diagrams for the top journeys, security design (authentication, authorisation, secrets, threat notes), deployment and environments, configuration, logging and monitoring, performance and scaling approach, a coding standards summary, and which FRs each module meets.

**data-design.md**: data model overview, ERD (Mermaid erDiagram), table or collection definitions (field, type, constraints, description), indexes, data lifecycle and retention, migrations approach, PII inventory and protection, backup and restore, sample data for tests (synthetic only).

**api-spec.md**: conventions (base URL, auth, versioning, errors, pagination), then for each endpoint: method, path, purpose, auth, request, response, error codes, and the FR it serves. Also cover rate limits and webhooks if there are any.

**adr/0001-stack-choice.md** (Architecture Decision Record): context, the options considered, the decision, the consequences, and the status (Accepted).

## 05-ux

**user-flows.md**: a Mermaid flowchart for each key journey, with entry points, decision points and error paths.

**wireframes.md**: for each key screen, a purpose line, an ASCII wireframe in a code block, the elements with their behaviour, the empty, loading and error states, the FR or US it covers, and responsive or mobile notes. Add a short UI style direction (tone, colours, typography) at the start.

## 06-quality

**test-plan.md** (IEEE 829 style): objectives, scope (in and out), test levels (unit, integration, system, acceptance), test types (functional, security, performance, usability, compatibility), environments and test data (synthetic), tools, entry and exit criteria, defect management, roles, schedule, risks, and the CI approach.

**test-cases.md** (System Test Cases): `TC-xx` with title, traces-to (`FR-xx` or `NFR-xx`), preconditions, steps, expected result, priority, and type. Write at least one case per FR, and cover negative and edge cases for the critical FRs.

## 07-project

**scope.md** (Project Scope Statement): scope description, deliverables, acceptance criteria, exclusions, constraints, assumptions.

**wbs.md** (Work Breakdown Structure): a hierarchical numbered list (1, 1.1, 1.1.1) down to work packages. Each package gets an estimate in days, a dependency and a milestone. Include a WBS dictionary table for the top-level packages and a Mermaid gantt for the milestones.

**roadmap.md**: milestones M0–Mn, each with its goal, deliverables, the FRs it delivers, exit criteria and target duration. M0 is always "repo, scaffold, CI, tooling".

**risk-register.md**: a table with columns ID, Risk, Category, Likelihood, Impact, Score, Mitigation, Owner, Trigger, Status. Seed it with the attacks that survived from the council verdict.

## glossary.md and docs/README.md
The glossary defines the domain and technical terms. The docs index lists every document with a one-line purpose and a suggested reading order.
