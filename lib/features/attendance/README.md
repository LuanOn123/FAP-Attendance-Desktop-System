# Member 3 integration

Receive a `Schedule` and the unique `ClassModel` from `ClassMappingService`.
Do not start attendance if mapping is missing or ambiguous.
Add server-side session/token/secret/student validation in dedicated handlers,
with authentication independent of the lecturer-only generic core endpoint.
