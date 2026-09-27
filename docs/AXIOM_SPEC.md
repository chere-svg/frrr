# Axiom Language Specification — v0.2 (Full)

## 1. Purpose

Axiom is a programming language for **scientific and mathematical research**: results are mathematically provable at compile time, execution is C-competitive, and the toolchain is designed so memory-safety and type-safety vulnerabilities are structurally excluded rather than tested for.

## 2. Design Pillars

| Pillar | Mechanism |
|---|---|
| Mathematically proven correctness | Full dependent types + refinement types, SMT-solved (Z3) at compile time |
| Zero runtime cost for proofs | Proof erasure before codegen |
| C-competitive performance | AOT via LLVM, monomorphized generics, no GC, auto-vectorization |
| Memory & security safety | Compile-time ownership/borrow-checking, no raw pointers, no `unsafe` in user code |
| Reproducibility | Deterministic floating-point, explicit evaluation order |
| Differentiability | Autodiff as a language primitive, not a library |
| Physical correctness | Units of measure checked at compile time |
| Heterogeneous compute | GPU/accelerator codegen as a first-class target |
| Adoption path | Python and C/Fortran interop from day one |

## 3. Type System

### 3.1 Dependent Types (shape-safe tensors)
```axiom
let a : Tensor<Float, [3, 4]> = ...
let b : Tensor<Float, [4, 5]> = ...
let c = matmul(a, b)          -- Tensor<Float, [3, 5]>, proven at compile time
matmul(a, Tensor<Float,[3,3]>) -- COMPILE ERROR: dimension mismatch
```

### 3.2 Refinement Types
```axiom
type Probability = Float where 0.0 <= self <= 1.0
type NonEmpty<T>  = List<T> where length(self) > 0
```

### 3.3 Dependent Function Contracts
```axiom
fn safe_divide(a : Float, b : Float where self != 0.0) -> Float = a / b
fn index<T, n>(arr : Vector<T, n>, i : Nat where self < n) -> T = ...
```

### 3.4 Units of Measure (NEW)
Physical quantities are typed by dimension, not just numeric type. Dimensional mismatches are compile errors, and unit conversion is automatic and checked.
```axiom
unit Meter, Second, Kilogram

type Velocity = Quantity<Meter / Second>
type Force    = Quantity<Kilogram * Meter / Second^2>

let d : Quantity<Meter>  = 100.0<Meter>
let t : Quantity<Second> = 9.58<Second>
let v : Velocity = d / t                 -- OK, dimensions divide correctly

let bad = d + t                          -- COMPILE ERROR: Meter + Second is not defined
```

### 3.5 Numerical Types for Research
```axiom
type BigInt        -- arbitrary precision integers
type BigFloat<p>   -- arbitrary precision floats, p = bits of precision
type Interval<T>   -- interval arithmetic, tracks [min, max] through computation
type Symbolic      -- symbolic expressions for computer-algebra workflows
```

## 4. Automatic Differentiation (NEW)

Autodiff is a compiler primitive, not a library, so it composes correctly with the type system, erases proof overhead, and works through control flow.

```axiom
fn loss(w : Tensor<Float,[n,m]>, x : Tensor<Float,[b,n]>, y : Tensor<Float,[b,m]>) -> Float =
  let pred = matmul(x, w)
  mean_squared_error(pred, y)

-- grad returns a function with the same signature but producing the gradient
-- w.r.t. the first argument. Reverse-mode by default; `grad_fwd` for forward-mode.
let dL_dw = grad(loss)(w, x, y)   -- Tensor<Float,[n,m]>, shape-matched to w automatically
```

Higher-order derivatives (`grad(grad(f))`), Jacobians (`jacobian(f)`), and Hessians (`hessian(f)`) are standard-library operators built on the same primitive.

## 5. Heterogeneous Compute / GPU Model (NEW)

Device placement is part of the type, so a shape-safe tensor is also placement-safe — you cannot accidentally run a CPU kernel on GPU-resident data or vice versa without an explicit (and checked) transfer.

```axiom
let x : Tensor<Float, [1024, 1024], Device.GPU> = to_device(cpu_tensor, Device.GPU)

@gpu
fn relu(x : Tensor<Float, [n,m], Device.GPU]) -> Tensor<Float, [n,m], Device.GPU] =
  max(x, 0.0)
```

`@gpu`-annotated functions compile through LLVM's NVPTX (CUDA) or SPIR-V (Vulkan/cross-vendor) backends. The borrow-checker and shape-checker run identically regardless of target device — a GPU kernel gets the same safety guarantees as CPU code, which is not true of CUDA C++.

## 6. SMT Solver Behavior & Proof Fallback (NEW)

Dependent-type checking can, in the worst case, be undecidable or slow. Axiom defines explicit behavior for this rather than leaving it implicit:

- **Default:** the compiler attempts automatic proof search with a configurable per-obligation timeout (default 2s).
- **On timeout/failure:** the compiler does not silently accept or hang — it reports the specific unproven obligation and offers two paths:
  1. **Tactic block** — the user supplies a manual proof sketch (`by { induction n; simp }`-style, Lean-inspired) that the compiler checks rather than searches for.
  2. **`assume` escape hatch** — loudly logged, requires a `--allow-assumptions` compiler flag, and is flagged in every build artifact's metadata so an assumed-not-proven pipeline can never silently pass as fully verified.
- **Proof caching:** successful proofs are cached and invalidated only when the relevant code changes, so incremental builds don't re-run expensive SMT queries.

## 7. Metaprogramming (NEW)

`comptime` blocks run at compile time and can generate code — used for things like N-dimensional stencil unrolling or generating symbolic-differentiation rules — without giving up type safety, since generated code is type-checked like any other.

```axiom
comptime fn unroll_stencil(n : Nat) -> Code = ...
```

Macros are hygienic (no accidental variable capture) and cannot generate `unsafe`-equivalent constructs, since none exist in the language.

## 8. Interop (NEW — critical for adoption)

### 8.1 Python interop
A bidirectional FFI bridge lets Axiom call NumPy/pandas/PyTorch/scikit-learn and vice versa. Values crossing the boundary are checked against Axiom's refinement/shape types at the boundary — a NumPy array with the wrong shape raises a typed error at the call site instead of corrupting Axiom's internal invariants.
```axiom
extern python "numpy" {
  fn np_fft(x : Tensor<Float,[n]>) -> Tensor<Complex,[n]>
}
```

### 8.2 C / Fortran / BLAS / LAPACK interop
`extern` blocks isolate FFI calls into an explicitly audited boundary layer. The compiler does not (and cannot) prove properties about the foreign code, and says so: every `extern` block requires a human-written contract describing pre/post-conditions, which the compiler checks at the Axiom-side boundary even though it can't verify the foreign implementation itself.
```axiom
extern c "liblapack" {
  fn dgesv(n : Int, a : Ptr<Float>, lda : Int) -> Int
    contract requires n > 0
}
```
Day-one standard library ships thin, safe wrappers over BLAS/LAPACK so users get optimized linear algebra without writing raw FFI themselves.

## 9. Visualization (NEW)

Standard-library `plot` module producing publication-quality static figures (line, scatter, histogram, heatmap) and rendering inline in the notebook kernel — no separate library required for the common case, with an escape hatch to Python's matplotlib/plotly via the interop layer for anything more advanced.

## 10. Package Ecosystem Bootstrap (NEW)

- `axm.toml` package manifest, semantic versioning.
- Central registry launches with first-party wrappers for the ~20 most-used scientific Python/C libraries (NumPy, SciPy, BLAS, LAPACK, pandas) so day-one users aren't starting from zero.
- Interop layer (Section 8) is the actual bootstrap strategy: Axiom does not need to "win" against the Python ecosystem before it's useful, since it can call into it safely from day one.

## 11. Error Message Design (NEW)

Type/proof errors are the primary adoption risk for a dependently-typed language, so error reporting is a first-class design target, not an afterthought:
- Structured, multi-part messages: what was expected, what was found, and the specific proof obligation that failed.
- `--why` flag prints the full proof trace / SMT counterexample in readable form.
- Shape mismatches render as a visual diff of the two shapes, not raw type dumps.
- The compiler suggests concrete fixes where possible (e.g., "insert `transpose(x)` to match expected shape").

## 12. Testing (NEW)

Refinement types double as property specifications: given `fn f(x : Float where x > 0) -> Float where result > 0`, the test framework can automatically generate property-based tests (QuickCheck-style) that search for counterexamples, in addition to normal unit tests.

## 13. Debugging (NEW)

- Debug builds retain proof metadata and full source maps even though release builds erase them, so a debugger can show *why* the compiler believed an access was safe.
- Standard LLDB/GDB integration via LLVM's debug-info format.
- Deterministic floating-point semantics (Section 2) enable exact replay/time-travel debugging for a given input — a run either fails the same way every time or the compiler flags where nondeterminism was introduced (e.g., an unordered reduction).

## 14. Versioning & Compatibility (NEW)

Because changing a function's proof obligations can break every caller's proofs, Axiom defines three compatibility levels beyond normal semver:
- **Source-compatible:** signatures unchanged.
- **Proof-compatible:** signatures unchanged in strength, but proof *search strategy* changed (may require re-verification but not code changes).
- **Proof-breaking:** obligations strengthened or weakened; requires a major version bump and migration shims (typed wrapper functions with the old contract, marked deprecated).

## 15. Memory & Ownership Model

No raw pointers, no manual `free`, no `unsafe` in user code. Ownership/borrowing resolved entirely at compile time; the compiled binary contains no GC and no reference counting. Effects (I/O, randomness, filesystem, network, GPU dispatch) are tracked in function signatures via `IO<T>`, so a function without that effect is provably incapable of touching the outside world.

## 16. Compilation Pipeline

```
Source (.axm)
  -> Parse -> AST
  -> Elaborate dependent types, solve constraints via SMT (Z3), apply fallback rules (Sec. 6)
  -> Macro/comptime expansion (Sec. 7)
  -> Proof erasure
  -> Monomorphize generics
  -> Borrow-check
  -> Lower to typed IR
  -> LLVM codegen -> native (CPU) or NVPTX/SPIR-V (GPU)
```
A lightweight bytecode VM remains for the interactive REPL/notebook, favoring iteration speed over throughput.

## 17. Error Handling

`Result<T, E>` and `Option<T>` only — no exceptions, no `null`.

## 18. Concurrency

Pure data-parallel operations over tensors/arrays. No shared mutable state; data races excluded by construction.

## 19. Syntax Samples

```axiom
fn main() -> IO<Unit> =
  print("hello, axiom")

fn gradient_step(w : Tensor<Float,[n,m]>, x : Tensor<Float,[b,n]>, y : Tensor<Float,[b,m]>)
    -> Tensor<Float,[n,m]> =
  let dL_dw = grad(loss)(w, x, y)
  w - (0.01 * dL_dw)

fn confidence_interval(data : NonEmpty<Float>) -> Interval<Float> =
  let m = mean(data)
  let s = stddev(data)
  m ± (1.96 * s / sqrt(length(data)))
```

## 20. Tooling Roadmap

Package manager, formatter, LSP, Jupyter-compatible kernel, `--why` diagnostics, LLDB/GDB integration, property-test runner.

## 21. Open Questions for v0.3

- Compiler host language: Rust (recommended) vs. OCaml.
- Exact scope of day-one stdlib beyond the BLAS/LAPACK/plotting wrappers already committed to.
- Governance model for the `extern` contract system (who audits foreign-code contracts in the public registry).
