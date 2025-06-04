# Filter Patterns

Filter patterns use simple glob-style wildcard patterns. A single asterisk `*` will match any character except `/`. A double asterisk `**` will match all the descendants of path.

|                         | `/home` | `/home/*` | `/home/**` | `/home/` | `/home/*/` | `/home/**/` |
| ----------------------- | :-----: | :-------: | :--------: | :------: | :--------: | :---------: |
| `/home`                 | **✔**   | **✘**     | **✔**      | **✘**    | **✘**      | **✔**       |
| `/home/alice`           | **✘**   | **✔**     | **✔**      | **✘**    | **✘**      | **✘**       |
| `/home/alice/projects`  | **✘**   | **✘**     | **✔**      | **✘**    | **✘**      | **✘**       |
| `/home/`                | **✘**   | **✔**     | **✔**      | **✔**    | **✘**      | **✔**       |
| `/home/alice/`          | **✘**   | **✘**     | **✔**      | **✘**    | **✔**      | **✔**       |
| `/home/alice/projects/` | **✘**   | **✘**     | **✔**      | **✘**    | **✘**      | **✔**       |

NOTE: Filter patterns ending in a doublestar `**` wildcard and no trailing path separator *will* match the parent path and descendants.

```terraform
# To exclude /home and all its descendants:
EXCLUDED_EXPORTS = ["/home/**"]
```

| Special Terms | Meaning                                                                                                                       |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `*`           | matches any sequence of non-path-separators                                                                                   |
| `/**/`        | matches zero or more directories                                                                                              |
| `?`           | matches any single non-path-separator character                                                                               |
| `[class]`     | matches any single non-path-separator character against a class of characters (see ["Character Classes"](#character-classes)) |
| `{alt1,...}`  | matches a sequence of characters if one of the comma-separated alternatives matches                                           |

Any character with a special meaning can be escaped with a backslash (`\`).

## Character Classes

Character classes support the following:

| Class      | Meaning                                                       |
| ---------- | ------------------------------------------------------------- |
| `[abc]`    | matches any single character within the set                   |
| `[a-z]`    | matches any single character in the range                     |
| `[^class]` | matches any single character which does *not* match the class |
| `[!class]` | same as `^`: negates the class                                |

### Combining include and exclude patterns

Include and exclude patterns can be combined. For an export to be accepted (and re-exported), the export *must* match an include pattern, and *must not* match an exclude pattern.
