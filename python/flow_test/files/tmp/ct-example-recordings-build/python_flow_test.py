# Simple Python program for trace recording testing.
# Mirrors the structure of the Rust/C/Nim flow tests:
# function calls, loops, and basic arithmetic.


def calculate_sum(a: int, b: int) -> int:
    """Add two numbers, double the result, then add 10."""
    total = a + b
    doubled = total * 2
    final = doubled + 10
    print(f"Sum: {total}")
    print(f"Doubled: {doubled}")
    print(f"Final: {final}")
    return final


def sum_with_for(n: int) -> int:
    """Sum 1..n using a for loop."""
    total = 0
    for i in range(1, n + 1):
        total += i
    return total


def sum_with_while(n: int) -> int:
    """Sum 1..n using a while loop."""
    total = 0
    i = 1
    while i <= n:
        total += i
        i += 1
    return total


def main() -> None:
    x = 10
    y = 32
    result = calculate_sum(x, y)
    print(f"Result: {result}")

    s1 = sum_with_for(9)
    print(f"sum with for {s1}")

    s2 = sum_with_while(9)
    print(f"sum with while {s2}")


if __name__ == "__main__":
    main()
