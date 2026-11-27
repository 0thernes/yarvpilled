module

public import Yarvpilled

/-!
# Axiom Audit for Yarvpilled Lean 4 Formalization

Audits `#print axioms` for every theorem in `Yarvpilled.Slots` (8 theorems)
and `Yarvpilled.Spec` (23 theorems) — 31 theorems total.
Every theorem must depend strictly on a subset of the three standard Lean
axioms `[propext, Classical.choice, Quot.sound]` (or no axioms), with zero
`sorryAx`, zero custom axioms, and zero native-compiler axioms.
-/

-- Yarvpilled.Slots (8 theorems)
#print axioms Yarvpilled.fillFirst_length
#print axioms Yarvpilled.fillFirst_alive
#print axioms Yarvpilled.alive_append
#print axioms Yarvpilled.alive_le_length
#print axioms Yarvpilled.spawn_le_cap
#print axioms Yarvpilled.spawn_alive
#print axioms Yarvpilled.population_le_cap
#print axioms Yarvpilled.spawn_full

-- Yarvpilled.Spec (23 theorems)
#print axioms Yarvpilled.regrow_food_le_max
#print axioms Yarvpilled.regrow_acc_lt
#print axioms Yarvpilled.regrow_monotone
#print axioms Yarvpilled.regrow_exact
#print axioms Yarvpilled.eat_conserves
#print axioms Yarvpilled.eat_take_le_bite
#print axioms Yarvpilled.eat_take_le_food
#print axioms Yarvpilled.bite_le_nine
#print axioms Yarvpilled.energy_identity
#print axioms Yarvpilled.gain_injective
#print axioms Yarvpilled.energy_identity_sum
#print axioms Yarvpilled.refund_bounded
#print axioms Yarvpilled.refund_ge
#print axioms Yarvpilled.energySensor_byte
#print axioms Yarvpilled.crowdSensor_le
#print axioms Yarvpilled.ageSensor_le
#print axioms Yarvpilled.energySensor_mono
#print axioms Yarvpilled.wrapCell_in_range
#print axioms Yarvpilled.wrapCell_eq_mod
#print axioms Yarvpilled.tick1_food_le
#print axioms Yarvpilled.tick1_eaten_mono
#print axioms Yarvpilled.tick1_dead_stays_dead
#print axioms Yarvpilled.tick1_energy_identity
