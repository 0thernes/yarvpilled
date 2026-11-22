/-!
# Integer part of the YARVPILLED world step

A specification of the discrete parts of one tick, mirroring
`ext/yarvpilled_native/kernel_c.c` / `ext/yarvpilled_rust/src/lib.rs` /
`lib/yarvpilled/world_ruby.rb`:

* food regrowth (8.8 fixed-point accumulator, clamped to 255)
* eating (bite 9 when grazing, 4 otherwise)
* energy bookkeeping (gain take + take/2, metabolism 3 + cost (+3 sprint))
* death refund (+40 food, clamped)
* sensor clamps
* the branch-free grid wrap used by the hand-written x86-64 crowd scan

What is NOT here: positions, headings, trig, collisions (IEEE-754 floats).
Those are covered by differential tests, not proofs. See docs/verification.md.
-/
namespace Yarvpilled

def foodMax : Nat := 255

/-- One food cell's regrowth: `(food', acc')`. -/
def regrow (food acc fert : Nat) : Nat × Nat :=
  (min (food + (acc + fert) / 256) foodMax, (acc + fert) % 256)

theorem regrow_food_le_max (f a r : Nat) : (regrow f a r).1 ≤ 255 := by
  simp only [regrow, foodMax]; omega

theorem regrow_acc_lt (f a r : Nat) : (regrow f a r).2 < 256 := by
  simp only [regrow]; omega

theorem regrow_monotone (f a r : Nat) (h : f ≤ 255) : f ≤ (regrow f a r).1 := by
  simp only [regrow, foodMax]; omega

/-- Below the clamp, regrowth loses nothing: the 8.8 fixed-point total is exact. -/
theorem regrow_exact (f a r : Nat) (h : f + (a + r) / 256 ≤ 255) :
    256 * (regrow f a r).1 + (regrow f a r).2 = 256 * f + a + r := by
  simp only [regrow, foodMax]; omega

/-- Bite size per action (0 graze, 1 left, 2 right, 3 sprint). -/
def bite (a : Nat) : Nat := if a % 4 = 0 then 9 else 4

/-- Eating from one cell: `(take, food')`. -/
def eat (food b : Nat) : Nat × Nat := (min food b, food - min food b)

theorem eat_conserves (f b : Nat) : (eat f b).2 + (eat f b).1 = f := by
  simp only [eat]; omega

theorem eat_take_le_bite (f b : Nat) : (eat f b).1 ≤ b := by
  simp only [eat]; omega

theorem eat_take_le_food (f b : Nat) : (eat f b).1 ≤ f := by
  simp only [eat]; omega

theorem bite_le_nine (a : Nat) : bite a ≤ 9 := by
  unfold bite; split <;> omega

def metabolism (cost : Int) (a : Nat) : Int := 3 + cost + (if a % 4 = 3 then 3 else 0)

def gain (take : Nat) : Int := (take : Int) + (take / 2 : Nat)

def energyStep (e : Int) (take : Nat) (cost : Int) (a : Nat) : Int :=
  e + gain take - metabolism cost a

/-- The energy accounting identity, per creature. -/
theorem energy_identity (e : Int) (t : Nat) (c : Int) (a : Nat) :
    energyStep e t c a - e = gain t - metabolism c a := by
  simp only [energyStep]; omega

/-- `take + take/2` is injective, so the per-creature take is recoverable from
the energy change. The property test `test_energy_accounting` relies on this. -/
theorem gain_injective (t u : Nat) (h : gain t = gain u) : t = u := by
  simp only [gain] at h; omega

/-- A creature's tick outcome: its take, cost and action. -/
structure Eat where
  take : Nat
  cost : Int
  act : Nat

def totalDelta : List Eat → Int
  | [] => 0
  | x :: xs => (gain x.take - metabolism x.cost x.act) + totalDelta xs

def totalTake : List Eat → Nat
  | [] => 0
  | x :: xs => x.take + totalTake xs

def totalMetab : List Eat → Int
  | [] => 0
  | x :: xs => metabolism x.cost x.act + totalMetab xs

def totalBonus : List Eat → Nat
  | [] => 0
  | x :: xs => x.take / 2 + totalBonus xs

/-- Population-level energy accounting: the sum of all energy changes equals
eaten food plus the half-bonus minus total metabolism. -/
theorem energy_identity_sum (xs : List Eat) :
    totalDelta xs = (totalTake xs : Int) + (totalBonus xs : Int) - totalMetab xs := by
  induction xs with
  | nil => simp [totalDelta, totalTake, totalBonus, totalMetab]
  | cons x xs ih => simp only [totalDelta, totalTake, totalBonus, totalMetab, gain] at *; omega

/-- Death refund: the corpse returns 40 food to its cell, clamped. -/
def refund (food : Nat) : Nat := min (food + 40) foodMax

theorem refund_bounded (f : Nat) : refund f ≤ 255 := by
  simp only [refund, foodMax]; omega

theorem refund_ge (f : Nat) (h : f ≤ 255) : f ≤ refund f := by
  simp only [refund, foodMax]; omega

/-! ## Sensors -/

/-- Energy sensor: `trunc(e / 4.0)` clamped to a byte (C truncates toward 0). -/
def energySensor (e : Int) : Int := max 0 (min (e.tdiv 4) 255)

def crowdSensor (n : Nat) : Nat := min n 15

def ageSensor (age : Nat) : Nat := min (age / 8) 255

theorem energySensor_byte (e : Int) : 0 ≤ energySensor e ∧ energySensor e ≤ 255 := by
  simp only [energySensor]; omega

theorem crowdSensor_le (n : Nat) : crowdSensor n ≤ 15 := by
  simp only [crowdSensor]; omega

theorem ageSensor_le (a : Nat) : ageSensor a ≤ 255 := by
  simp only [ageSensor]; omega

/-- More energy never reads lower (monotone sensor). -/
theorem energySensor_mono (e f : Int) (h : 0 ≤ e) (hef : e ≤ f) : energySensor e ≤ energySensor f := by
  simp only [energySensor]
  have h1 : e.tdiv 4 = e / 4 := Int.tdiv_eq_ediv_of_nonneg h
  have h2 : f.tdiv 4 = f / 4 := Int.tdiv_eq_ediv_of_nonneg (by omega)
  rw [h1, h2]; omega

/-! ## Grid wrap of the hand-written asm crowd scan

`crowd_x86_64.S` computes the neighbour cell as `t + g` if `t < 0`,
`t - g` if `t >= g`, else `t` (cmov, no idiv), where `t = gy + oy` lies in
`[-1, g]`. The C kernel computes `(t + g) % g`. They agree on that range. -/

def wrapCell (t g : Int) : Int := if t < 0 then t + g else if t ≥ g then t - g else t

theorem wrapCell_in_range (t g : Int) (hg : 0 < g) (h1 : -1 ≤ t) (h2 : t ≤ g) :
    0 ≤ wrapCell t g ∧ wrapCell t g < g := by
  unfold wrapCell; split <;> (try split) <;> omega

theorem wrapCell_eq_mod (t g : Int) (hg : 0 < g) (h1 : -1 ≤ t) (h2 : t ≤ g) :
    wrapCell t g = (t + g) % g := by
  unfold wrapCell
  split
  · exact (Int.emod_eq_of_lt (by omega) (by omega)).symm
  · split
    · have ht : t = g := by omega
      subst ht
      rw [show t + t = 2 * t by omega, Int.mul_emod_left]; omega
    · rw [Int.add_emod_right]; exact (Int.emod_eq_of_lt (by omega) (by omega)).symm

/-! ## One creature alone in one food cell

The executable mirror (`Mirror.lean`) runs exactly this function; the Ruby test
`test_formal_mirror.rb` checks every backend against it tick by tick. -/

structure One where
  food : Nat
  acc : Nat
  fert : Nat
  energy : Int
  cost : Int
  age : Nat
  eaten : Nat
  alive : Bool
  deriving Repr

def tick1 (s : One) (a : Nat) : One :=
  if !s.alive then
    let (f, c) := regrow s.food s.acc s.fert
    { s with food := f, acc := c }
  else
    let (f, c) := regrow s.food s.acc s.fert
    let (t, f') := eat f (bite a)
    let e := energyStep s.energy t s.cost a
    let age := s.age + 1
    if e ≤ 0 ∨ age ≥ 900 then
      { s with food := refund f', acc := c, energy := e, age := age, eaten := s.eaten + t, alive := false }
    else
      { s with food := f', acc := c, energy := e, age := age, eaten := s.eaten + t }

theorem tick1_food_le (s : One) (a : Nat) : (tick1 s a).food ≤ 255 := by
  unfold tick1
  have hr := regrow_food_le_max s.food s.acc s.fert
  split
  · simp only; exact hr
  · simp only
    split
    · exact refund_bounded _
    · simp only [eat]; omega

theorem tick1_eaten_mono (s : One) (a : Nat) : s.eaten ≤ (tick1 s a).eaten := by
  unfold tick1; split
  · simp
  · simp only; split <;> simp

theorem tick1_dead_stays_dead (s : One) (a : Nat) (h : s.alive = false) : (tick1 s a).alive = false := by
  unfold tick1; simp [h]

theorem tick1_energy_identity (s : One) (a : Nat) (h : s.alive = true) :
    (tick1 s a).energy - s.energy =
      gain (eat (regrow s.food s.acc s.fert).1 (bite a)).1 - metabolism s.cost a := by
  unfold tick1
  simp only [h, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  split <;> simp only [energyStep] <;> omega

end Yarvpilled
