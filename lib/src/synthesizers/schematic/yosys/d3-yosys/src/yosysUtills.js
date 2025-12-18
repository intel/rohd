export function getPortSide(portName, direction, nodeName) {
    if (direction === "input" && nodeName === "MUX" && portName === "S") {
        return "SOUTH";
    }
    if (direction === "output") {
        return "EAST";
    }
    if (direction === "input") {
        return "WEST";
    }
    throw new Error("Unknown direction " + direction);
}

export function orderClkAndRstPorts(node) {
    let index = 0;
    for (let port of node.ports) {
        let dstIndex = index;
        if (port.hwMeta.name === "CLK") {
            dstIndex = node.ports.length - 1;
        } else if (port.hwMeta.name === "ARST") {
            dstIndex = node.ports.length - 2;
        }
        if (index !== dstIndex) {
            let otherPort = node.ports[dstIndex];
            node.ports[dstIndex] = port;
            node.ports[index] = otherPort;
            otherPort.properties.index = port.properties.index;
            port.properties.index = dstIndex;
        }
        ++index;
    }
}

function iterNetnameBits(netnames, fn) {
    for (const [netname, netObj] of Object.entries(netnames)) {
        for (const bit of netObj.bits) {
            fn(netname, bit, Number.isInteger(bit), isConst(bit));
        }
    }
}

export function getNetNamesDict(yosysModule) {
    let netnamesDict = {}; // yosys bits (netId): netname

    iterNetnameBits(yosysModule.netnames, (netname, bit, isInt, isStr) => {
        if (isInt) {
            netnamesDict[bit] = netname;
        } else if (!isStr) {
            throw new Error("Invalid type in bits: " + typeof bit);
        }
    });
    return netnamesDict;
}

export function isConst(val) {
    return (typeof val === "string");
}

export function getConstNodeName(nameArray) {
    let nodeName = nameArray.reverse().join("");
    nodeName = ["0b", nodeName].join("");
    if (nodeName.match(/^0b[01]+$/g)) {
        let res = BigInt(nodeName).toString(16);
        return ["0x", res].join("");
    }
    return nodeName;
}

export function addEdge(edge, portId, edgeDict, startIndex, width) {
    let edgeArr = edgeDict[portId];
    if (edgeArr === undefined) {
        edgeArr = edgeDict[portId] = [];
    }
    edgeArr[startIndex] = [edge, width];
}

export function getSourceAndTarget2(edge) {
    return [edge.sources, edge.targets, false, true];
}

export function getSourceAndTargetForCell(edge) {
    return [edge.targets, edge.sources, true, false];
}

export function getPortNameSplice(startIndex, width) {
    if (width === 1) {
        return `[${startIndex}]`;
    } else if (width > 1) {
        let endIndex = startIndex + width;
        return `[${endIndex}:${startIndex}]`;
    }

    throw new Error("Incorrect width" + width);

}


export function hideChildrenAndNodes(node, yosysModule) {
    if (yosysModule !== null) {
        if (node.children.length === 0 && node.edges.length === 0) {
            delete node.children
            delete node.edges;

        } else {
            node._children = node.children;
            delete node.children
            node._edges = node.edges;
            delete node.edges;
        }
    }
}


function updatePortIndices(ports) {
    let index = 0;
    for (let port of ports) {
        port.properties.index = index;
        ++index;
    }
}

function dividePorts(ports) {
    let north = [];
    let east = [];
    let south = [];
    let west = [];

    for (let port of ports) {
        let side = port.properties.side;
        if (side === "NORTH") {
            north.push(port);
        } else if (side === "EAST") {
            east.push(port);
        } else if (side === "SOUTH") {
            south.push(port);
        } else if (side === "WEST") {
            west.push(port);
        } else {
            throw new Error("Invalid port side: " + side);
        }
    }

    return [north, east, south, west];
}

export function convertPortOrderingFromYosysToElk(node) {
    let [north, east, south, west] = dividePorts(node.ports);
    node.ports = north.concat(east, south.reverse(), west.reverse());
    updatePortIndices(node.ports);

}

export function getTopModuleName(yosysJson) {
    let topModuleName = undefined;
    for (const [moduleName, moduleObj] of Object.entries(yosysJson.modules)) {
        if (moduleObj.attributes.top) {
            topModuleName = moduleName;
            break;
        }
    }

    if (topModuleName === undefined) {
        throw new Error("Cannot find top");
    }

    return topModuleName;
}
