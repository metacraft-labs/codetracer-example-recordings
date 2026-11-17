# Simple Ruby program for trace recording testing.
# Mirrors the structure of the Rust/C/Nim flow tests:
# function calls, loops, and basic arithmetic.

def calculate_sum(a, b)
  total = a + b
  doubled = total * 2
  final_val = doubled + 10
  puts "Sum: #{total}"
  puts "Doubled: #{doubled}"
  puts "Final: #{final_val}"
  final_val
end

def sum_with_for(n)
  total = 0
  (1..n).each do |i|
    total += i
  end
  total
end

def sum_with_while(n)
  total = 0
  i = 1
  while i <= n
    total += i
    i += 1
  end
  total
end

x = 10
y = 32
result = calculate_sum(x, y)
puts "Result: #{result}"

s1 = sum_with_for(9)
puts "sum with for #{s1}"

s2 = sum_with_while(9)
puts "sum with while #{s2}"
