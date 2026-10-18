"""Generates spec/math-generated.json: random expressions with results from Python's decimal
module at 34 digits, half-even (same per-operation rounding as Java MathContext.DECIMAL128).

    python3 spec/generate_cases.py > spec/math-generated.json
"""
import json
import random
import sys
from decimal import Decimal, Context, ROUND_HALF_EVEN, DivisionByZero, InvalidOperation

CTX = Context(prec=34, rounding=ROUND_HALF_EVEN, traps=[DivisionByZero, InvalidOperation])
LIMIT = Decimal(10) ** 34
OPS = {"+": CTX.add, "−": CTX.subtract, "×": CTX.multiply, "÷": CTX.divide}


class Overflow(Exception):
    pass


def checked(d):
    if abs(d) >= LIMIT:
        raise Overflow
    return d


def literal(rng):
    digits = "".join(rng.choice("0123456789") for _ in range(rng.choice([1, 2, 3, 6, 12, 20, 34, 36])))
    point = rng.randint(0, len(digits))
    text = digits[:point] + ("." + digits[point:] if point < len(digits) else "")
    text = text if not text.startswith(".") else "0" + text
    return text, checked(CTX.plus(Decimal(text)))


def expression(rng, depth):
    if depth == 0 or rng.random() < 0.3:
        text, value = literal(rng)
        if rng.random() < 0.15:
            return "−" + text, checked(CTX.minus(value))
        return text, value
    op = rng.choice(list(OPS))
    (lt, lv), (rt, rv) = expression(rng, depth - 1), expression(rng, depth - 1)
    wrap = lambda t: t if t.replace(".", "").isdigit() else "(" + t + ")"
    return wrap(lt) + op + wrap(rt), checked(OPS[op](lv, rv))


def canonical(d):
    s = format(d, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main():
    rng = random.Random(34)
    cases = []
    while len(cases) < 3000:
        try:
            text, value = expression(rng, 3)
        except (DivisionByZero, InvalidOperation, Overflow):
            continue  # both errors are covered by hand in math-cases.json
        cases.append({"id": f"gen-{len(cases)}", "input": text, "result": canonical(value)})
    json.dump({"version": 1, "precision": 34, "rounding": "half_even", "cases": cases},
              sys.stdout, ensure_ascii=False, indent=0)


if __name__ == "__main__":
    main()
