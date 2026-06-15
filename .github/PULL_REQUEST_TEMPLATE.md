## Summary

<!-- One paragraph: what changes, why. -->

## Type

- [ ] Bug fix (non-breaking)
- [ ] Feature (non-breaking)
- [ ] Breaking change
- [ ] Documentation only
- [ ] Refactor / internal

## Component

- [ ] Smart contracts
- [ ] Agent runtime
- [ ] Frontend
- [ ] Docs
- [ ] CI / tooling

## Testing

<!-- For contracts: `forge test -vvv` output snippet -->
<!-- For runtime: list which tests you ran + result -->

## Checklist

- [ ] Tests pass locally (`forge test` and/or `python tests/...`)
- [ ] No new compiler warnings
- [ ] No console.log / print debug statements left in
- [ ] Updated docs / README if behavior changed
- [ ] Added/updated tests for the change
- [ ] If smart contract change: ran `forge snapshot` and checked gas diff
- [ ] If smart contract change: ran Slither (`slither contracts/`) and addressed any new findings

## Security considerations

<!-- For any contract change: list the access control / reentrancy / arithmetic implications. -->
<!-- If none: write "n/a — no state changes / no external calls / no token movement". -->

## Related issues

<!-- Closes #123 -->
