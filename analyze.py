from prettytable import PrettyTable

# Input times (A, B, C, D)
times = [174.184, 102.176, 62.286, 37.918]

# Calculate speedup
speedup = [times[0] / t for t in times]

# Calculate parallel efficiency
efficiency = [speedup[i] / (2 ** i) for i in range(len(speedup))]

# Create a table
headers = ["Metric", "Sequential", "Dual-Core", "Quad-Core", "Octa-Core"]
table = PrettyTable(headers)

table.add_row(["Tiempos"] + [f"{t:.3f}" for t in times])
table.add_row(["Speedup"] + [f"{s:.3f}" for s in speedup])
table.add_row(["Ef. Paralela"] + [f"{e:.3f}" for e in efficiency])

# Print the table
print(table)