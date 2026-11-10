# Document sets and folder structures by idea type

Choose the set that matches the concept's **Idea type**. Mixed ideas (for example a content channel with an app) take the primary type's set plus the specific documents they need from the other type.

**Independent review (SKILL.md step 6).** Only the software set has an SRS, an SDD and a test plan, so only software ideas get the independent review, along with mixed ideas that took those three documents. For content, service, research, hardware, programme and other ideas, skip the review and say so in the reply. Don't adapt the briefs to other documents.

## software (apps, platforms, plugins, APIs, tools)

```
<slug>/
  README.md
  docs/
    README.md                     docs index
    00-ideation/                  council-verdict.md, refined-concept.md
    01-business/                  project-brief.md, project-charter.md, brd.md, stakeholder-register.md
    02-product/                   prd.md, personas.md, user-stories.md
    03-requirements/              urs.md, srs.md, traceability-matrix.md
    04-architecture/              sdd.md, data-design.md, api-spec.md, adr/0001-stack-choice.md
    05-ux/                        user-flows.md, wireframes.md
    06-quality/                   test-plan.md, test-cases.md
    07-project/                   scope.md, wbs.md, roadmap.md, risk-register.md
    glossary.md
  src/                            (empty, .gitkeep)
  tests/                          (empty, .gitkeep)
```
Skip `api-spec.md` if there is no API, and say so in the SDD. For WordPress plugins and themes, add `docs/04-architecture/wp-integration.md`, covering hooks, capabilities, the settings API and multisite.

## content (channels, media, courses, explainer series)

```
<slug>/
  README.md
  docs/
    00-ideation/
    01-strategy/       channel-brief.md, audience-personas.md, positioning.md, monetisation.md
    02-content/        content-pillars.md, format-guide.md, series-plan.md, episode-template.md, content-calendar.md
    03-production/     production-pipeline.md (tools, AI tools, workflow), brand-guide.md, asset-checklist.md
    04-growth/         distribution-plan.md, kpis.md, community-plan.md
    05-project/        roadmap.md, budget.md, risk-register.md
  assets/              brand/, templates/, raw/ (.gitkeep)
  episodes/            (.gitkeep)
```

## service (agencies, consulting, training, local businesses)

```
<slug>/
  README.md
  docs/
    00-ideation/
    01-business/       business-plan.md, value-proposition.md, pricing.md, financial-model.md (tables)
    02-market/         customer-segments.md, competitor-analysis.md, go-to-market.md, sales-playbook.md
    03-operations/     service-blueprint.md, sop-index.md, sops/, tools-and-suppliers.md
    04-legal/          registration-and-compliance.md, contract-templates-needed.md
    05-project/        launch-plan.md, kpis.md, risk-register.md
```

## research (studies, surveys, evaluations, data projects)

```
<slug>/
  README.md
  docs/
    00-ideation/
    01-design/         research-brief.md, research-questions.md, methodology.md, sampling-plan.md, ethics-and-consent.md
    02-instruments/    questionnaire-spec.md, data-dictionary.md, qa-checks.md
    03-analysis/       analysis-plan.md, dashboard-spec.md
    04-project/        workplan.md, budget.md, stakeholder-register.md, risk-register.md, dissemination-plan.md
  data/                raw/, clean/ (.gitkeep; add data/ to .gitignore)
  analysis/            (.gitkeep)
```

## hardware (devices, 3D-printed products, IoT)

```
<slug>/
  README.md
  docs/
    00-ideation/
    01-product/        product-brief.md, requirements.md (functional + physical + environmental), use-cases.md
    02-design/         design-spec.md, bom.md (bill of materials with costs), cad-notes.md, electronics.md, firmware-spec.md
    03-build/          prototype-plan.md, assembly-guide.md, print-settings.md
    04-quality/        test-plan.md, safety-and-compliance.md
    05-project/        roadmap.md, budget.md, suppliers.md, risk-register.md
  cad/  firmware/  photos/   (.gitkeep)
```

## programme (events, community initiatives, NGO or government programmes)

```
<slug>/
  README.md
  docs/
    00-ideation/
    01-design/         concept-note.md, theory-of-change.md, logframe.md, stakeholder-map.md
    02-delivery/       implementation-plan.md, activity-schedule.md, roles-and-responsibilities.md
    03-me/             me-framework.md (indicators, baselines, targets, data sources), reporting-templates.md
    04-resources/      budget.md, funding-strategy.md, partnerships.md
    05-project/        risk-register.md, communication-plan.md
```

## other
Combine the closest sets. Always include a brief, scope, roadmap, budget or effort estimate, and risk register.
