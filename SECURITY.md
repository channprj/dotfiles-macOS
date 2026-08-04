# Security

Do not commit credentials, private keys, access tokens, or machine-local secret
configuration to this repository.

## Local scan

Install [Gitleaks](https://github.com/gitleaks/gitleaks), then scan both the
working tree and local Git history:

```sh
brew install gitleaks
./scripts/check-secrets.sh
```

The command redacts every detected value. It also includes reflogs so that a
secret removed by a normal commit is still caught locally.

## If a secret is committed

1. Revoke or rotate the credential at its provider immediately.
2. Remove it from every reachable Git ref and reflog.
3. Force-push rewritten refs with a lease only after coordinating with every
   contributor.
4. Ask the Git host to purge cached views, pull-request refs, and unreachable
   objects when the old commit is still retrievable.
5. Run `./scripts/check-secrets.sh` again before resuming normal work.

Never test a suspected credential against a live service to decide whether it
is safe to keep.
