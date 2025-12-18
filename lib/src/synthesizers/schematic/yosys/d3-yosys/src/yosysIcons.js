export function yosysTranslateIcons(node, cell) {
    let meta = node.hwMeta;
    const t = cell.type;

    if (t === "$mux" || t === "$pmux") {
        meta.cls = "Operator";
        meta.name = "MUX";
    } else if (t === "$gt") {
        meta.cls = "Operator";
        meta.name = "GT";
    } else if (t === "$lt") {
        meta.cls = "Operator";
        meta.name = "LT";
    } else if (t === "$ge") {
        meta.cls = "Operator";
        meta.name = "GE";
    } else if (t === "$le") {
        meta.cls = "Operator";
        meta.name = "LE";
    } else if (t === "$not" || t === "$logic_not") {
        meta.cls = "Operator";
        meta.name = "NOT";
    } else if (t === "$logic_and" || t === "$and") {
        meta.cls = "Operator";
        meta.name = "AND";
    } else if (t === "$logic_or" || t === "$or") {
        meta.cls = "Operator";
        meta.name = "OR";
    } else if (t === "$xor") {
        meta.cls = "Operator";
        meta.name = "XOR";
    } else if (t === "$eq") {
        meta.cls = "Operator";
        meta.name = "EQ";
    } else if (t === "$ne") {
        meta.cls = "Operator";
        meta.name = "NE";
    } else if (t === "$add") {
        meta.cls = "Operator";
        meta.name = "ADD";
    } else if (t === "$sub") {
        meta.cls = "Operator";
        meta.name = "SUB";
    } else if (t === "$mul") {
        meta.cls = "Operator";
        meta.name = "MUL";
    } else if (t === "$div") {
        meta.cls = "Operator";
        meta.name = "DIV";
    } else if (t === "$slice") {
        meta.cls = "Operator";
        meta.name = "SLICE";
    } else if (t === "$concat") {
        meta.cls = "Operator";
        meta.name = "CONCAT";
    } else if (t === "$adff") {
        meta.cls = "Operator";
        let arstPolarity = cell.parameters["ARST_POLARITY"];
        let clkPolarity = cell.parameters["CLK_POLARITY"];
        if (clkPolarity && arstPolarity) {
            meta.name = "FF_ARST_clk1_rst1";
        } else if (clkPolarity) {
            meta.name = "FF_ARST_clk1_rst0";
        } else if (arstPolarity) {
            meta.name = "FF_ARST_clk0_rst1";
        } else {
            meta.name = "FF_ARST_clk0_rst0";
        }
    } else if (t === "$dff") {
        meta.cls = "Operator";
        meta.name = "FF";
    } else if (t === "$shift" || t === "$shiftx") {
        meta.cls = "Operator";
        meta.name = "SHIFT";
    } else if (t === "$dlatch") {
        meta.cls = "Operator";
        let enPolarity = cell.parameters["EN_POLARITY"];
        if (enPolarity) {
            meta.name = "DLATCH_en1";
        } else {
            meta.name = "DLATCH_en0";

        }
    }
}