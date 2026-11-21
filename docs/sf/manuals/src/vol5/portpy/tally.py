# tally.py - a Python original: dynamic types, a dict and a list, an exception,
# and automatic memory. Its Z98 twin is tally.z98.
rows = [("apples", 3), ("pears", 2), ("apples", 5), ("pears", 4)]


def tally(rows):
    totals = {}
    for name, qty in rows:
        totals[name] = totals.get(name, 0) + qty
    return totals


def average(totals):
    if len(totals) == 0:
        raise ValueError("empty tally")
    return sum(totals.values()) // len(totals)


def main():
    totals = tally(rows)
    for name in ("apples", "pears"):
        print(name, totals[name])
    print("average", average(totals))
    try:
        average({})
    except ValueError:
        print("caught empty tally")


main()
