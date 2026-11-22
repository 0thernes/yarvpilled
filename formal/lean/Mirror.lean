import Yarvpilled
/-!
Executable mirror of `Yarvpilled.tick1`, for differential testing against the
real backends (test/test_formal_mirror.rb).

stdin, one case per line:  food fert energy cost thresh a1 a2 ... an
stdout, one line per tick: fa en ag | energy food eaten alive born
(sensors are read before the tick, like World#sense then World#act; a dead
creature senses 0 0 0 and reports energy "-").
-/
open Yarvpilled

def ints (l : String) : List Int :=
  (l.splitOn " ").filterMap (fun w => if w.isEmpty then none else w.toInt?)

def runCase : List Int → List String
  | food :: fert :: energy :: cost :: thresh :: acts =>
    let s0 : One := { food := food.toNat, acc := 0, fert := fert.toNat, energy := energy,
                      cost := cost, age := 0, eaten := 0, alive := true }
    let step := fun (st : One × List String) (a : Int) =>
      let s := st.1
      let sense := if s.alive then s!"{s.food} {energySensor s.energy} {ageSensor s.age}" else "0 0 0"
      let s' := tick1 s a.toNat
      let e := if s'.alive then toString s'.energy else "-"
      let born := s'.alive && decide (s'.energy ≥ thresh)
      (s', st.2 ++ [s!"{sense} | {e} {s'.food} {s'.eaten} {s'.alive} {born}"])
    (acts.foldl step (s0, [])).2
  | _ => ["bad case"]

def main : IO Unit := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  let mut line ← stdin.getLine
  while !line.isEmpty do
    for out in runCase (ints (line.replace "\n" "")) do
      stdout.putStrLn out
    stdout.putStrLn "."
    line ← stdin.getLine
