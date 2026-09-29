# tagged_tag_member_shadow_xmod — a member named `tag` is shadowed by the synthetic `.tag` (FX16-F fix round 1, I2)

Sema's field-access tag arm already makes the synthetic `.tag` shadow a real
union member named `tag` (it returns the tag type for any `.tag` field access
on a tagged union). Lowering's generic tagged-union read arm used to find the
real member `tag` first and read its PAYLOAD, so `u.tag` returned the payload
bits and A+ compares/switches dispatched from them:

- PRE (payload read): `5 0 0 9 5 0 5 0` — `u.tag` printed 5, `u.tag == .tag`
  was false (5 vs ordinal 0), `switch (u.tag)` fell to `else` (9), the pointer
  read and param compare read 5 too, and the raw tag store then read back the
  still-unchanged payload.
- POST (synthetic tag, golden `expected.txt` `0 1 0 1 0 1 1 1`): `u.tag`
  reads the ordinal (0 for the active `tag` variant), `.tag` sugar compares and
  switches by ordinal, the P1 pointer path and the `ptrParam` compare agree,
  and `u.tag = 1` writes then reads the synthetic tag (1).

The rule (Language_Spec §1.3): a member named `tag` is permanently shadowed by
the synthetic tag — accept the collision silently but avoid naming a member
`tag`. Zero pre-existing corpus dirs use a member named `tag`, so the fix moves
no other dir.
