// Simple JavaScript program for trace recording testing.
// Mirrors the structure of the Python/Ruby flow tests:
// function calls, loops, and basic arithmetic.

function calculate_sum(a, b) {
  var sum_val = a + b;
  var doubled = sum_val * 2;
  var final_val = doubled + 10;
  console.log("Sum: " + sum_val);
  console.log("Doubled: " + doubled);
  console.log("Final: " + final_val);
  return final_val;
}

function sum_with_for(n) {
  var total = 0;
  for (var i = 1; i <= n; i++) {
    total += i;
  }
  return total;
}

function sum_with_while(n) {
  var total = 0;
  var i = 1;
  while (i <= n) {
    total += i;
    i += 1;
  }
  return total;
}

function main() {
  var x = 10;
  var y = 32;
  var result = calculate_sum(x, y);
  console.log("Result: " + result);

  var s1 = sum_with_for(9);
  console.log("sum with for " + s1);

  var s2 = sum_with_while(9);
  console.log("sum with while " + s2);
}

main();
