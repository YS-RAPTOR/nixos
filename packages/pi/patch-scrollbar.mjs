import { readFile, writeFile } from "node:fs/promises";

const path = process.argv[2];
if (path === undefined) throw new Error("Expected the Pi TUI layout.js path");

let source = await readFile(path, "utf8");
const replacements = [
  [
    'import { extractAnsiCode, getGraphemeCellRange, sliceByColumn, visibleWidth } from "./utils.js";',
    'import { getGraphemeCellRange, sliceByColumn, stripTerminalSequences, visibleWidth } from "./utils.js";',
  ],
  [
    `function styleScrollbarCell(line, column, totalWidth, style) {
    if (isImageLine(line))
        return line;
    const graphemeRange = getGraphemeCellRange(line, column);
    const start = graphemeRange?.start ?? column;
    const end = graphemeRange?.end ?? column + 1;
    const before = sliceByColumn(line, 0, start, true);
    const target = sliceByColumn(line, start, end - start, true);
    const after = sliceByColumn(line, end, Math.max(0, totalWidth - end), true);
    let targetPrefix = "";
    let targetIndex = 0;
    while (targetIndex < target.length) {
        const ansi = extractAnsiCode(target, targetIndex);
        if (!ansi)
            break;
        targetPrefix += ansi.code;
        targetIndex += ansi.length;
    }
    const targetText = target.slice(targetIndex) || " ".repeat(end - start);
    const beforePadding = " ".repeat(Math.max(0, start - visibleWidth(before)));
    return \`${"${before}${beforePadding}${targetPrefix}${style(targetText)}${after}"}\`;
}`,
    `function styleScrollbarCell(line, column, totalWidth, style) {
    if (isImageLine(line))
        return line;
    const graphemeRange = getGraphemeCellRange(line, column);
    const start = graphemeRange?.start ?? column;
    const end = graphemeRange?.end ?? column + 1;
    const target = stripTerminalSequences(sliceByColumn(line, start, end - start, true));
    const targetText = target || " ".repeat(end - start);
    return compositeTuiLine(line, style(targetText), start, end - start, totalWidth);
}`,
  ],
];

for (const [before, after] of replacements) {
  if (!source.includes(before)) {
    throw new Error(`Unable to find expected Pi TUI source in ${path}`);
  }
  source = source.replace(before, after);
}

await writeFile(path, source);
