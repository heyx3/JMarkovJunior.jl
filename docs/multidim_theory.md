Below is a chat with Google Gemini about the math behind multidimensional block symmetries.
It was extremely valuable in planning that part of the DSL,
  so I'm holding onto this until the implementation details are actually implemented.

----------------------------------------

> I'm trying to quantify box permutations (rotations and flips) in multidimensional space, as simply as possible. Here is my proposal:
> 
> * Pick a world axis and a direction (negative or positive) along it for the box's first axis to orient along.
> * Pick a DIFFERENT world axis and a direction along it, for the box's second axis to orient along.
> * Repeat for each box axis.
> 
> Does this cover all rotations and flips? Are there any redundancies?


To put it simply: **Yes**, your proposal covers every possible orientation (rotations and flips), but it contains **redundancies**.

You have essentially described a process of mapping the box's local coordinate system onto the world’s coordinate system. While it works, the "Repeat for each box axis" step is where the logic over-specifies the problem.

### 1. Does it cover all rotations and flips?

**Yes.** By specifying a world axis and direction for every local axis, you are defining a complete **Transformation Matrix**. Since you allow any world axis and any direction (), you can reach every state in the hyperoctahedral group (the symmetry group of an -dimensional cube).

### 2. Are there redundancies?

**Yes.** The redundancy comes from the fact that axes in a box are mutually perpendicular (orthogonal). Once you fix the first few axes, the remaining ones are constrained.

* **The Orthogonality Constraint:** In  dimensions, once you have picked directions for  axes, the final axis **must** lie on the only remaining world axis. It cannot be "picked" freely from any world axis; it is forced into the last remaining slot.
* **The Chirality (Handedness) Constraint:** Even the *direction* of that final axis might be constrained if you only want **rotations** (which preserve the "handedness" of the box). If you allow flips (reflections), then you have 2 choices for the final axis (). If you only allow rotations, the final axis direction is mathematically fixed by the "Right-Hand Rule" once the others are placed.

### The Correct Counting Logic

To see the redundancies clearly, look at how the valid choices diminish as you go. You don't repeat the full "pick any world axis" logic for every step.

| Step | Choice for Box Axis | Number of Options |
| --- | --- | --- |
| **1** | Pick any world axis and direction |  |
| **2** | Pick any *remaining* world axis and direction |  |
| **3** | Pick any *remaining* world axis and direction |  |
| **...** | ... | ... |
| **D** | The axis is forced to the last spot. (Choice is just ) |  |

The total number of unique states (rotations + flips) is the product of these choices:


* **** represents the reflection choices (flipping axes).
* **** represents the permutation choices (swapping axes).

Would you like me to show you how to restrict this to **only** rotations (no mirror images)?

> I specified "DIFFERENT" axis, so we are already in agreement I believe. The last box axis only has one choice left.
> 
> I would like to allow arbitrary constraints on axis+direction choices for each box axis. For example, maybe I want the first two "horizontal" axes to stay horizontal but still rotate and flip freely, then the Z axis must stay vertical and not flip, and finally the W axis must stay W but can flip.
> 
> Say I use this syntax to describe how each box axis may map to the world: `{ [ x, y], [ x, y ], [ +Z ], [ W ] }`.
> 
> How can I further constrain the first two "horizontal" axes to only rotate and not flip?

You are absolutely correct about the "DIFFERENT" axis logic handling the redundancy. If you treat your list as "pick from this set, but you can't pick a world axis that was already used," you have a solid permutation generator.

To answer your specific question about the "horizontal" axes:

The problem with your current syntax `{ [ x, y], [ x, y ] ... }` is that it defines **independent** possibilities for each axis. A "rotation only" constraint is a **dependent** relationship between axes (specifically, their order and sign relative to each other).

To constrain the first two axes to "rotate but not flip," you need to enforce **Chirality (Handedness)**.

### The Logic: What implies a "Flip"?

In your 2D sub-space (the x,y plane), there are 8 possible states. 4 are rotations, 4 are flips.

* **Rotation:** You preserve the relative "left/right" relationship of the axes. (e.g., If X is forward, Y is right).
* **Flip:** You invert that relationship. (e.g., If X is forward, Y is left).

Mathematically, you enforce this by checking the **Determinant** of the transformation matrix for those specific axes.

* **Determinant = +1:** Rotation (Valid)
* **Determinant = -1:** Flip (Invalid)

### How to express this in your syntax

You cannot express this purely by listing allowed axes for `BoxAxis0` and `BoxAxis1`. You must group them and apply a **"Positive Parity"** (or Handedness) constraint to that group.

Here is a proposed syntax extension:

`{ Group(0, 1): "SameHandedness", 2: [+Z], 3: [W] }`

This rule filters your permutations. Here is how the filter logic works in practice for your `{ [x,y], [x,y] }` example:

#### 1. Valid Rotations (Keep these)

These pairs preserve the "X cross Y = +Z" winding order:

* **0°:** `Axis0 -> +x`, `Axis1 -> +y`
* **90°:** `Axis0 -> +y`, `Axis1 -> -x`
* **180°:** `Axis0 -> -x`, `Axis1 -> -y`
* **270°:** `Axis0 -> -y`, `Axis1 -> +x`

#### 2. Invalid Flips (Discard these)

These pairs break the winding order (equivalent to swapping axes or negating just one):

* `Axis0 -> +y`, `Axis1 -> +x` (Diagonal flip)
* `Axis0 -> +x`, `Axis1 -> -y` (Mirror across X)
* `Axis0 -> -x`, `Axis1 -> +y` (Mirror across Y)
* etc.

### Summary of the Constraint

To implement this in your code/logic, you simply add one check after generating a candidate permutation:

**"Does the cross product of my chosen World Axis 0 and World Axis 1 match the direction of the original Box Axis 0 and Box Axis 1?"**

If the cross product points in the *opposite* direction (or if the determinant is -1), you have accidentally flipped the box, and you should reject that configuration.

> So I add to my constraint syntax the ability to tie two axes `A` and `B` together by chirality with `A(B)` or `B(A)`. The following should restrict the first two axes to only rotate:
> 
> `{ [ x, y ], [ x, y ], [+Z], [W], 1(2) }`
> 
> Does this give the user full control over eliminating cube orientations, or are there sets of eliminations that can't be specified?

This syntax is very powerful, but the answer is **No, it does not give you full control.**

There is a specific class of eliminations that this syntax cannot specify: **Correlated Constraints** (or "Entangled" states).

Your system defines valid options for each axis independently (the sets) and valid relationships between pairs (the chirality). However, it cannot link the choice of Axis 1 to the choice of Axis 3.

### The "Ghost" Permutation Problem

Because you are defining lists of allowed axes for each slot, your system generates a **Product Space**. If you try to define two specific, distinct orientations, your system will accidentally authorize every valid mix-and-match combination of them.

#### The Counter-Example: "All or Nothing"

Imagine you want to allow exactly two states for a 3D box:

1. **State A:** The box is standard (`+x`, `+y`, `+z`).
2. **State B:** The box is inverted (`-x`, `-y`, `-z`).

*(Note: In 3D, inverting all 3 axes is a "flip" (Determinant -1). If you want rotations only, assume 4D or 2D where double/quad flips are rotations. For the sake of this logic, let's just look at the permutations).*

To allow **State A** and **State B**, your syntax must look like this:
`{ [+x, -x], [+y, -y], [+z, -z] }`

**The Failure:**
This syntax successfully permits A and B. However, because the choices are independent, it **also** permits:

* `{ +x, +y, -z }` (Mixed state)
* `{ -x, +y, -z }` (Mixed state)
* etc.

These "Ghost" states are geometrically valid (they are orthogonal), so the "Different Axis" rule won't catch them. Your `A(B)` chirality constraint also won't catch them all. For example, `{ +x, +y, -z }` might be a flip, but `{ +x, -y, -z }` is a valid rotation that you didn't ask for, but your syntax allows.

### What is missing?

To have "Full Control," you would need a syntax that supports **Conditionals**:
*"Axis 1 can be `-x`, **IF AND ONLY IF** Axis 2 is `-y`."*

Your current syntax says:
*"Axis 1 can be `-x`. Separately, Axis 2 can be `-y`."*

### Summary

* **Can it describe any single orientation?** Yes.
* **Can it describe "All Rotations"?** Yes.
* **Can it describe "Keep Z vertical, spin X and Y"?** Yes.
* **Can it describe "Orientation A OR Orientation B" (arbitrary subsets)?** **No.** It will leak "hybrid" orientations that combine features of A and B.

If your goal is standard game physics (keeping characters upright, preventing upside-down cameras), your syntax is perfect. If your goal is a puzzle game where a hypercube must match exact, non-trivial discrete states, this syntax will be insufficient.

> My goal is more like the latter. Can my syntax be extended or should it be rewritten entirely? For example maybe just add a suffix for explicit allowed orientations?

To handle the "All or Nothing" problem (correlated constraints), your syntax needs a fundamental upgrade. You cannot simply add a suffix; you must break the assumption that each axis chooses its fate independently.

Here are the two best paths forward: **Extend your syntax with "Coupling"** or **Rewrite it using "Templates."**

### Option 1: The Syntax Extension (The "Coupled Tuple")

**Best for:** When you want to keep your current logic but fix the "ghost permutation" issue.

The problem with `Axis 1: [A, B]` and `Axis 2: [C, D]` is that it automatically permits `AC`, `AD`, `BC`, and `BD`.
To fix this, allow users to define **Groups of Axes** that must be chosen as a single unit.

**Proposed Syntax:**
Instead of defining axes individually, define them as a tuple:
`{ (1, 2): [ (+x, +y), (-x, -y) ], 3: [+z], 4: [w] }`

* **Meaning:** "Pick a pair for Axis 1 & 2. You may pick `(+x, +y)` OR `(-x, -y)`. You may **not** pick `(+x, -y)`."
* **Why it works:** It forces the selection logic to pick from a list of *vectors*, not scalars. This eliminates the "mixed" states.
* **Redundancy Check:** You still need your "Different Axis" logic to ensure that if Group A picks `+x`, Group B doesn't also pick `+x`.

### Option 2: The Rewrite (The "Template" System)

**Best for:** If your constraints are mostly "State A OR State B" (arbitrary subsets) rather than procedural rules like "keep Z vertical."

If you find yourself writing complex rules just to allow 3 specific orientations, it is easier to invert the logic: **List the allowed states explicitly.**

**Proposed Syntax:**
`Allowed: [ "Standard", "Inverted", "LayingDown" ]`

Where you define "templates" elsewhere:

* `Standard = { +x, +y, +z, +w }`
* `Inverted = { -x, -y, -z, -w }`

**Why consider this?**
In 4D procedural generation, you often only want a tiny fraction of the 384 (or more) possible orientations. Generating all of them and then filtering 99% of them out via complex syntax is inefficient. It is often cleaner to just "whitelist" the 5 or 6 valid states you actually want.

### Recommendation

If you are building a **general physics engine** (where things mostly rotate freely but have some limits), use **Option 1**. The "Tuple" syntax is a powerful way to express constraints like "The X and Y axes are locked together in a specific rotation, but Z is free."

**Revised Syntax Example (Option 1):**

```text
// Allow standard rotation, OR fully inverted.
// Disallow "mixed" states (like upside-down X but normal Y).
{ 
  (0, 1, 2): [ (+x, +y, +z), (-x, -y, -z) ], 
  3: [ +w, -w ]
}

```

> Sounds good! Finally, how can we determine in the general case if a given constraint is malformed?

This is a classic **Constraint Satisfaction Problem (CSP)**. Since you are likely dealing with  dimensions, you don't need complex heuristics. The "general case" validation is best handled by a three-step failure check: **Syntax, Orthogonality, and Chirality.**

Here is the algorithm to determine if a constraint set is malformed.

### 1. Structural Check (Syntax)

Before doing any math, check if the definition makes sense as a data structure.

* **Duplicate Definition:** Does the constraint try to define `BoxAxis 0` twice? (e.g., appearing in two different tuples).
* **Out of Bounds:** Does it reference `WorldAxis 5` in a 4D space?
* **Incomplete Grouping:** If you use tuples like `(0, 1)`, are both 0 and 1 actually defined?

### 2. The "Self-Collision" Check (Local Orthogonality)

This is the most common error. A user might accidentally ask for two different box axes to map to the *same* world axis.

* **Rule:** For every "Allowed Option" in your list (whether it's a single axis or a tuple), the selected world axes must be **unique**.
* **The Test:**
For every tuple/set defined:
1. Take the absolute value of the world axes (ignore +/- sign).
2. Does `Abs(WorldAxis_A) == Abs(WorldAxis_B)`?
3. If **YES**, the constraint is malformed. You cannot map Box X and Box Y both to World Vertical.



### 3. The "Empty Set" Check (Global Satisfiability)

A constraint is "malformed" if it results in **zero** possible valid states. This often happens due to "Chirality Conflicts" (impossible rotations).

* **The Scenario:** The user fixes `X` to `North`, `Y` to `East`, and implies `Z` is `Up` (standard), but then adds a generic rule: "Must be a Left-Handed Flip."
* **The Conflict:** The fixed axes describe a Right-Handed system, but the generic rule demands a Left-Handed one.
* **The General Algorithm:**
Since the search space for box orientations is small (), you do not need complex predictive logic. The most robust validation is to simply **run the generator**:
1. Initialize a list of all unassigned world axes.
2. Filter the available choices for Axis 0 based on your constraints.
3. Pick the first valid choice.
4. Recurse for Axis 1 (using only *remaining* world axes).
5. ...
6. **Final Step:** Calculate the Determinant of the resulting matrix.
* If `Determinant == +1`: It's a Rotation.
* If `Determinant == -1`: It's a Flip.


7. **Result:** If the recursive search returns 0 valid results, the constraint is malformed (Over-Constrained).



### Summary Checklist for Your Code

If you are implementing this validation function, here is the pseudocode logic:

```python
def ValidateConstraints(constraints):
    # 1. Check for Duplicate Box Axes
    if len(constraints.keys()) != len(set(constraints.keys())):
        return "Error: Box Axis defined multiple times."

    # 2. Check Local Orthogonality (Tuple consistency)
    for axes_tuple, allowed_vectors in constraints.items():
        for vector_set in allowed_vectors:
            # Check if any world axis is reused inside this single option
            # e.g. defined as (+x, +x)
            if HasDuplicates(Abs(vector_set)):
                return "Error: Constraint requires non-orthogonal axes."

    # 3. Run Solver (The ultimate test)
    valid_permutations = FindAllValidPermutations(constraints)
    if len(valid_permutations) == 0:
        return "Error: Constraints are contradictory (Zero valid states found)."
    
    return "Valid"

```

### A Note on Chirality (The "Handedness" Trap)

If you allow the user to specify `AllowedChirality: "RotationOnly"`, you must check the **Determinant** in Step 3.

* In 3D, if the user locks 2 axes, the 3rd is forced.
* If `CrossProduct(UserAxis1, UserAxis2)` points in the **opposite** direction of `UserAxis3`, then `RotationOnly` is impossible. The solver will correctly return 0 results.