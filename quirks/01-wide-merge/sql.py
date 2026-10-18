"""Statement generator for the wide-merge quirk: sql.py <kind> <columns> <args...>

Column i (1-based) is c<i>, its type cycles through seven types so the generated code resembles a
real wide table.
"""
import sys

TYPES = ["varchar", "bigint", "double", "timestamp(6)", "date", "decimal(18,2)", "boolean"]


def expr(i: int, salt: str) -> str:
    """A value of column i for row n, NULL on some rows, different between source and target when salt differs."""
    t = TYPES[(i - 1) % len(TYPES)]
    v = f"(n * {i} + {salt})"
    value = {
        "varchar": f"CAST({v} AS varchar)",
        "bigint": f"CAST({v} AS bigint)",
        "double": f"CAST({v} AS double) / 7",
        "timestamp(6)": f"CAST(TIMESTAMP '2024-01-01 00:00:00' + {v} * INTERVAL '1' SECOND AS timestamp(6))",
        "date": f"DATE '2024-01-01' + {v} * INTERVAL '1' DAY",
        "decimal(18,2)": f"CAST({v} AS decimal(18,2))",
        "boolean": f"{v} % 2 = 0",
    }[t]
    return f"IF(n % {i + 2} = 0, NULL, {value}) AS c{i}"


def ctas(table: str, cols: int, location: str, salt: str, rows: int) -> str:
    """A wide Iceberg table of `rows` rows."""
    select = ", ".join(["n AS id"] + [expr(i, salt) for i in range(1, cols + 1)])
    return (f"CREATE TABLE {table} WITH (table_type = 'ICEBERG', is_external = false, location = '{location}') "
            f"AS SELECT {select} FROM UNNEST(sequence(1, {rows})) AS r(n)")


def check_join(src: str, tgt: str, cols: int, style: str) -> str:
    """The changed-rows join of a check-strategy snapshot: an OR over every column."""
    if style == "distinct":
        changed = " OR ".join(f"s.c{i} IS DISTINCT FROM t.c{i}" for i in range(1, cols + 1))
    else:  # the expression dbt's check strategy generates per column
        changed = " OR ".join(
            f"(t.c{i} <> s.c{i} OR ((t.c{i} IS NULL) AND NOT (s.c{i} IS NULL)) OR ((NOT t.c{i} IS NULL) AND (s.c{i} IS NULL)))"
            for i in range(1, cols + 1))
    return f"SELECT count(*) FROM {src} s JOIN {tgt} t ON s.id = t.id AND ({changed})"


def merge(src: str, tgt: str, cols: int) -> str:
    """A MERGE that updates every column."""
    names = [f"c{i}" for i in range(1, cols + 1)]
    sets = ", ".join(f"{c} = s.{c}" for c in names)
    return (f"MERGE INTO {tgt} t USING {src} s ON t.id = s.id "
            f"WHEN MATCHED THEN UPDATE SET {sets} "
            f"WHEN NOT MATCHED THEN INSERT (id, {', '.join(names)}) VALUES (s.id, {', '.join('s.' + c for c in names)})")


kind, cols, *args = sys.argv[1:]
cols = int(cols)
if kind == "ctas":
    print(ctas(args[0], cols, args[1], args[2], int(args[3])))
elif kind == "join":
    print(check_join(args[0], args[1], cols, args[2]))
elif kind == "merge":
    print(merge(args[0], args[1], cols))
