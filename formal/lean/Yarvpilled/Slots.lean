/-!
# Slot allocation and the population bound

`spawn` reuses the first dead slot, else appends while `used < cap`, else
fails (`nil` in Ruby). Mirrors `world_spawn` in world.c and `WorldRuby#spawn`.
-/
namespace Yarvpilled

def fillFirst : List Bool → Option (List Bool)
  | [] => none
  | false :: r => some (true :: r)
  | true :: r => (fillFirst r).map (true :: ·)

def spawn (s : List Bool) (cap : Nat) : Option (List Bool) :=
  match fillFirst s with
  | some s' => some s'
  | none => if s.length < cap then some (s ++ [true]) else none

def alive : List Bool → Nat
  | [] => 0
  | b :: r => (if b then 1 else 0) + alive r

theorem fillFirst_length : ∀ (s s' : List Bool), fillFirst s = some s' → s'.length = s.length
  | [], _, h => by simp [fillFirst] at h
  | false :: r, s', h => by simp [fillFirst] at h; subst h; simp
  | true :: r, s', h => by
    simp only [fillFirst, Option.map_eq_some_iff] at h
    obtain ⟨t, ht, rfl⟩ := h
    simp [fillFirst_length r t ht]

theorem fillFirst_alive : ∀ (s s' : List Bool), fillFirst s = some s' → alive s' = alive s + 1
  | [], _, h => by simp [fillFirst] at h
  | false :: r, s', h => by simp [fillFirst] at h; subst h; simp [alive]; omega
  | true :: r, s', h => by
    simp only [fillFirst, Option.map_eq_some_iff] at h
    obtain ⟨t, ht, rfl⟩ := h
    simp [alive, fillFirst_alive r t ht]; omega

theorem alive_append (s : List Bool) : alive (s ++ [true]) = alive s + 1 := by
  induction s with
  | nil => simp [alive]
  | cons b r ih => simp [alive, ih]; omega

theorem alive_le_length : ∀ s : List Bool, alive s ≤ s.length
  | [] => by simp [alive]
  | b :: r => by have := alive_le_length r; cases b <;> simp [alive] <;> omega

/-- Population bound: spawning never takes the slot array past capacity. -/
theorem spawn_le_cap (s s' : List Bool) (cap : Nat) (hs : s.length ≤ cap)
    (h : spawn s cap = some s') : s'.length ≤ cap := by
  unfold spawn at h
  split at h
  · rename_i t ht; simp at h; subst h; rw [fillFirst_length s t ht]; exact hs
  · split at h
    · simp at h; subst h; simp; omega
    · simp at h

/-- Every successful spawn adds exactly one living creature. -/
theorem spawn_alive (s s' : List Bool) (cap : Nat) (h : spawn s cap = some s') :
    alive s' = alive s + 1 := by
  unfold spawn at h
  split at h
  · rename_i t ht; simp at h; subst h; exact fillFirst_alive s t ht
  · split at h
    · simp at h; subst h; exact alive_append s
    · simp at h

/-- Consequently the living population never exceeds capacity. -/
theorem population_le_cap (s s' : List Bool) (cap : Nat) (hs : s.length ≤ cap)
    (h : spawn s cap = some s') : alive s' ≤ cap :=
  Nat.le_trans (alive_le_length s') (spawn_le_cap s s' cap hs h)

/-- A full world (no dead slot, at capacity) rejects the spawn. -/
theorem spawn_full (s : List Bool) (cap : Nat) (hfull : fillFirst s = none) (hc : cap ≤ s.length) :
    spawn s cap = none := by
  unfold spawn; rw [hfull]; simp; omega

end Yarvpilled
