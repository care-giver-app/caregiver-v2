# Runbook

Day-to-day operations for the Caregiver v2 monorepo.

## The dev loop

1. Branch from `main`:

   ```bash
   git checkout main && git pull
   git checkout -b feat/<short-name>
   ```

2. Make changes.
3. Run local checks:

   ```bash
   pnpm exec prettier --check .
   pnpm --filter @caregiver/infra test
   (cd api && go test ./...)
   (cd shared/go-common && go test ./...)
   ```

4. Commit using Conventional Commits (`feat:`, `fix:`, etc.). Lefthook enforces the format on commit.
5. Push and open a PR:

   ```bash
   gh pr create --fill
   ```

6. CI deploys your branch to dev automatically. The `cdk-diff` comment shows infra changes.
7. Once green, merge:

   ```bash
   gh pr merge --squash --delete-branch
   ```

   Merge triggers the prod deploy.

## Adding a new HTTP endpoint

Every new endpoint touches **three places**: the OpenAPI spec, the Go mux, and the CDK route registration. Forgetting the CDK route is the most common trap — the path will silently 404 at API Gateway before reaching Lambda.

1. Add the path + schema to `shared/openapi/openapi.yaml`.
2. Run codegen (pre-commit will also run this for you):

   ```bash
   pnpm --filter @caregiver/types-ts run build
   (cd shared/types-go && make codegen)
   cp shared/openapi/openapi.yaml shared/types-swift/Sources/CaregiverAPI/openapi.yaml
   ```

3. Write a failing handler test in `api/internal/handlers/`.
4. Implement the handler.
5. Wire the route into the Go mux at `api/cmd/lambda/mux.go`:

   ```go
   mux.Handle("GET /my-path", handlers.NewMyHandler(...))
   ```

6. **Register the route on the API Gateway HTTP API** in `infra/lib/api-stack.ts`, after the existing `httpApi.addRoutes` blocks:

   ```ts
   httpApi.addRoutes({
     path: '/my-path',
     methods: [apigw.HttpMethod.GET],
     integration: new integ.HttpLambdaIntegration('MyPathIntegration', this.apiFunction),
   });
   ```

7. Run tests:

   ```bash
   (cd api && go test ./...)
   pnpm --filter @caregiver/infra test
   ```

8. Commit, push, open PR.

## Adding a feature flag

1. Add the flag definition to `infra/lib/appconfig-schema.json`:

   ```json
   "feat_my_thing": {
     "type": "object",
     "required": ["enabled"],
     "properties": { "enabled": { "type": "boolean" } }
   }
   ```

2. Add it to `infra/lib/appconfig-content.ts` with `enabled: false`.
3. Write an ADR at `docs/adr/NNNN-feat-my-thing.md` describing the flag, default, and retirement criteria.
4. Add code that reads the flag via `flags.Client.Get(ctx)` and checks `flags["feat_my_thing"].(map[string]any)["enabled"]`.
5. After deploy, toggle the flag in the AWS AppConfig console.

## Adding an ADR

1. Copy `docs/adr/_template.md` to `docs/adr/NNNN-kebab-title.md` with the next number.
2. Fill in context, options, decision, consequences.
3. Commit with `docs: ADR-NNNN <title>`.

## Common operations

### See what's deployed

```bash
aws cloudformation list-stacks --region us-east-2 \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE | grep Caregiver
```

`BillingStack` lives in `us-east-1`; query that region separately for it.

### Tail Lambda logs

```bash
aws logs tail /aws/lambda/<function-name> --follow
```

### Manually trigger an alarm (test pipeline)

```bash
aws cloudwatch set-alarm-state \
  --alarm-name caregiver-prod-api-errors \
  --state-value ALARM \
  --state-reason "Pipeline test"
```

Reset with `--state-value OK` once verified.

### Cost check

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -v-30d +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics UnblendedCost
```

## Troubleshooting

| Symptom                                | Likely cause                            | Action                                                         |
| -------------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| CI lint fails on Prettier              | Unformatted files committed             | `pnpm exec prettier --write . && git commit --amend --no-edit` |
| Commit rejected                        | Bad commit message                      | Reword with Conventional Commits prefix                        |
| `cdk diff` shows surprise changes      | CDK or context drift                    | Read the diff, compare with what your code says                |
| Lambda 500 with "missing required env" | Forgot to add an env var in CDK         | Add to `api-stack.ts`, redeploy                                |
| New endpoint 404s in dev/prod          | Forgot to register the CDK route        | Add `httpApi.addRoutes(...)` block in `infra/lib/api-stack.ts` |
| AppConfig fetch returns stale value    | Extension cache TTL                     | Wait 45s, or restart the Lambda runtime                        |
| Prod deploy fails on new region        | CDKToolkit not bootstrapped that region | `cdk bootstrap aws://<acct>/<region>` from a privileged shell  |

## Links

- Spec: [`docs/specs/2026-06-06-f1-engineering-practices-baseline-design.md`](specs/2026-06-06-f1-engineering-practices-baseline-design.md)
- ADRs: [`docs/adr/`](adr/)
- Plans: [`docs/plans/`](plans/)
