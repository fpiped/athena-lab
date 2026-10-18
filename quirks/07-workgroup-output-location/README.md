# 07 workgroup-output-location

**Claim.** On a work group that overrides client-side settings, an `OutputLocation` passed to
StartQueryExecution is replaced by the work group's and nothing in the API says so; a CTAS
`external_location` on the same work group is rejected instead.

**Documented.** "If you specify client-side settings in your queries but run them in a workgroup that
overrides the settings, the queries will run, but the workgroup settings will be used"; the console
notifies users, the API is not said to
([Override client-side settings](https://docs.aws.amazon.com/athena/latest/ug/workgroups-settings-override.html)).

**Script.** `start-query-execution --result-configuration OutputLocation=<requested>` with
`SELECT 1` on the enforcing and on the open work group; prints the StartQueryExecution response keys,
whether GetQueryExecution's `ResultConfiguration.OutputLocation` is under the requested prefix, the
objects written there, every GetQueryExecution field, and any field mentioning override or enforce.
Then a CTAS with `external_location` on the enforcing work group.

**Result** (2026-10-18, Athena engine version 3): REPRODUCED.

- Enforcing: query succeeds, the location is the work group's, nothing written under the requested
  prefix, StartQueryExecution returns only `QueryExecutionId`, no GetQueryExecution field signals the
  override.
- Open: the requested location is used.
- CTAS on the enforcing work group: `InvalidRequestException: The Create Table As Select query failed because it was submitted with an 'external_location' property to an Athena Workgroup that enforces a centralized output location for all queries. Please remove the 'external_location' property and resubmit the query.`
