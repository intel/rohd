import {yosysTranslateIcons} from "./yosysIcons.js";
import {
    getPortSide,
    getPortNameSplice,
    isConst,
    addEdge,
    getConstNodeName,
    getTopModuleName,
    getNetNamesDict,
    orderClkAndRstPorts,
    hideChildrenAndNodes,
    getSourceAndTarget2,
    getSourceAndTargetForCell,
    convertPortOrderingFromYosysToElk
} from "./yosysUtills.js";

function getNodePorts(node, dict){
    for (let port of node.ports) {
        dict[port.id] = port;
    }

}
function getPortIdToPortDict(node) {
    let PortIdToPortDict = {};

    getNodePorts(node, PortIdToPortDict);
    for (let child of node.children) {
        getNodePorts(child, PortIdToPortDict);
    }

    return PortIdToPortDict;
}
function getNodeIdToNodeDict(node,) {
    let nodeIdToNodeDict = {};
    nodeIdToNodeDict[node.id] = node;
    for (let child of node.children) {
        nodeIdToNodeDict[child.id] = child;
    }
    return nodeIdToNodeDict;
}

function getPortToEdgeDict(edges) {
    let portToEdgeDict = {};
    for (let edge of edges) {
        let targets = edge.targets;
        let sources = edge.sources;
        for (let [_, portId] of sources) {
            portToEdgeDict[portId] = edge;
        }

        for (let [_, portId] of targets) {
            portToEdgeDict[portId] = edge;
        }
    }
    return portToEdgeDict;
}

function getChildSourcePorts(ports) {
    let sourcePorts = [];
    for(let port of ports) {
        if (port !== undefined && port.direction === "INPUT") {
            sourcePorts.push(port);
        }
    }

    return sourcePorts;
}

function getEdgeTargetsIndex(targets, portId) {
    for(let i = 0; i < targets.length; ++i) {
        let target = targets[i];
        let [_, targetPortId] = target;

        if (portId === targetPortId) {
            return i;
        }
    }
    throw new Error("PortId was not found");

}
function aggregateTwoNodes(childSourcePorts, targetNode, targetPort, portIdToEdgeDict) {
    let i = 0;
    if (targetPort.properties.index !== 0) {
        throw new Error("Port index is not zero, need to regenerate indices in port labels");
    }
    for (let oldTargetPort of childSourcePorts) {
        let oldTargetPortId = oldTargetPort.id;
        let edge = portIdToEdgeDict[oldTargetPortId];
        let edgeTargetsIndex = getEdgeTargetsIndex(edge.targets, oldTargetPortId);
        edge.targets[edgeTargetsIndex][0] = targetNode.id;
        let newTargetPortIndex = targetPort.properties.index + i;
        if (i === 0) {
            targetNode.ports[newTargetPortIndex] = oldTargetPort;
        }
        else {
            targetNode.ports.splice(newTargetPortIndex, 0, oldTargetPort)
        }
        oldTargetPort.properties.index = newTargetPortIndex;
        ++i;
    }


}

function getChildTargetPortId(child) {
    for (let port of child.ports) {
        if (port !== undefined && port.direction === "OUTPUT")
        {
            return port.id;
        }
    }

    throw new Error("Concat child has no target");
}

function aggregate(node, childrenConcats, portIdToEdgeDict, portIdToPortDict, nodeIdToNodeDict) {
    let edgesToDelete = new Set();
    let childrenToDelete = new Set();

    for (let child of childrenConcats) {
        let childTargetPortId = getChildTargetPortId(child);
        let edge = portIdToEdgeDict[childTargetPortId];
        if (edge === undefined) {
            continue;
        }
        let targets = edge.targets;

       if (targets !== undefined && targets.length === 1) {
            let [nodeId, portId] = targets[0];
            let targetNode = nodeIdToNodeDict[nodeId];
            let targetPort = portIdToPortDict[portId];
            let childSourcePorts = getChildSourcePorts(child.ports);
            if (targetNode === undefined) {
                throw new Error("Target node of target port is undefined");
            }
            if (targetNode.hwMeta.cls === "Operator" && targetNode.hwMeta.name === "CONCAT") {
                aggregateTwoNodes(childSourcePorts, targetNode, targetPort, portIdToEdgeDict)
                edgesToDelete.add(edge.id);
                childrenToDelete.add(child.id);
            }
        }
    }
    node.children = node.children.filter((c) => {
        return !childrenToDelete.has(c.id);
    });
    node.edges = node.edges.filter((e) => {
        return !edgesToDelete.has(e.id);
    });
}

function fillConcats(children) {
    let concats = [];
    for (let child of children) {
        if (child.hwMeta.cls === "Operator" && child.hwMeta.name === "CONCAT") {
            concats.push(child);
        }
    }
    return concats;

}

function aggregateConcants(node) {
    let concats = fillConcats(node.children);
    let portIdToEdgeDict = getPortToEdgeDict(node.edges);
    let portIdToPortDict = getPortIdToPortDict(node);
    let nodeIdToNodeDict = getNodeIdToNodeDict(node);
    aggregate(node, concats, portIdToEdgeDict, portIdToPortDict, nodeIdToNodeDict);
}

class LNodeMaker {
    constructor(name, yosysModule, idCounter, yosysModules, hierarchyLevel, nodePortNames) {
        this.name = name;
        this.yosysModule = yosysModule;
        this.idCounter = idCounter;
        this.yosysModules = yosysModules;
        this.hierarchyLevel = hierarchyLevel;
        this.nodePortNames = nodePortNames;
        this.childrenWithoutPortArray = [];
        this.nodeIdToCell = {};
    }

    make() {
        if (this.name === undefined) {
            throw new Error("Name is undefined");
        }

        let node = this.makeNode(this.name);

        if (this.yosysModule) {
            // cell with module definition, load ports, edges and children from module def. recursively
            this.fillPorts(node, this.yosysModule.ports, (p) => {
                return p.direction
            }, undefined);
            this.fillChildren(node);
            this.fillEdges(node);

            if (node.children !== undefined && node.children.length > 0) {
                aggregateConcants(node);
            }

        }

        if (node.children !== undefined) {
            for (let child of node.children) {
                convertPortOrderingFromYosysToElk(child);
                if (child.hwMeta.cls === "Operator" && child.hwMeta.name.startsWith("FF")) {
                    orderClkAndRstPorts(child);
                }
            }
        }

        if (this.hierarchyLevel > 1) {
            hideChildrenAndNodes(node, this.yosysModule);
        }

        node.hwMeta.maxId = this.idCounter - 1;
        return node;
    }
    makeNode(name) {
        let node = {
            "id": this.idCounter.toString(), //generate, each component has unique id
            "hwMeta": { // [d3-hwschematic specific]
                "name": name, // optional str
                "cls": "", // optional str
                "maxId": 2, // max id of any object in this node used to avoid re-counting object if new object is generated
            },
            "properties": { // recommended renderer settings
                "org.eclipse.elk.portConstraints": "FIXED_ORDER", // can be also "FREE" or other value accepted by ELK
                "org.eclipse.elk.layered.mergeEdges": 1
            },
            "ports": [],    // list of LPort
            "edges": [],    // list of LEdge
            "children": [], // list of LNode
        };
        ++this.idCounter;
        return node;
    }

    fillPorts(node, ports, getPortDirectionFn, cellObj) {
        const isSplit = cellObj !== undefined && cellObj.type === "$slice";
        const isConcat = cellObj !== undefined && cellObj.type === "$concat";
        let portByName = this.nodePortNames[node.id];
        if (portByName === undefined) {
            portByName = {};
            this.nodePortNames[node.id] = portByName;
        }
        for (let [portName, portObj] of Object.entries(ports)) {
            let originalPortName = portName;
            if (isSplit || isConcat) {
                if (portName === "Y") {
                    portName = "";
                }
                if (isSplit) {
                    if (portName === "A") {
                        portName = getPortNameSplice(cellObj.parameters.OFFSET, cellObj.parameters.Y_WIDTH);
                    }
                } else if (isConcat) {
                    let par = cellObj.parameters;
                    if (portName === "A") {
                        portName = getPortNameSplice(0, par.A_WIDTH);
                    } else if (portName === "B") {
                        portName = getPortNameSplice(par.A_WIDTH, par.B_WIDTH);
                    }
                }
            }
            let direction = getPortDirectionFn(portObj);
            this.makeLPort(node.ports, portByName, originalPortName, portName, direction, node.hwMeta.name);
        }
    }

    makeLPort(portList, portByName, originalName, name, direction, nodeName) {
        if (name === undefined) {
            throw new Error("Name is undefined");
        }

        let portSide = getPortSide(name, direction, nodeName);
        let port = {
            "id": this.idCounter.toString(),
            "hwMeta": { // [d3-hwschematic specific]
                "name": name,
            },
            "direction": direction.toUpperCase(), // [d3-hwschematic specific] controls direction marker
            "properties": {
                "side": portSide,
                "index": 0 // The order is assumed as clockwise, starting with the leftmost port on the top side.
                // Required only for components with "org.eclipse.elk.portConstraints": "FIXED_ORDER"
            },
            "children": [], // list of LPort, if the port should be collapsed rename this property to "_children"
        };
        port.properties.index = portList.length;
        portList.push(port);
        portByName[originalName] = port;
        ++this.idCounter;
        return port;
    }

    fillChildren(node) {
        // iterate all cells and lookup for modules and construct them recursively
        for (const [cellName, cellObj] of Object.entries(this.yosysModule.cells)) {
            let moduleName = cellObj.type; //module name
            let cellModuleObj = this.yosysModules[moduleName];
            let nodeBuilder = new LNodeMaker(cellName, cellModuleObj, this.idCounter, this.yosysModules,
                this.hierarchyLevel + 1, this.nodePortNames);
            let subNode = nodeBuilder.make();
            this.idCounter = nodeBuilder.idCounter;
            node.children.push(subNode);
            yosysTranslateIcons(subNode, cellObj);
            this.nodeIdToCell[subNode.id] = cellObj;
            if (cellModuleObj === undefined) {
                if (cellObj.port_directions === undefined) {
                    // throw new Error("[Todo] if modules does not have definition in modules and its name does not \
                    // start with $, then it does not have port_directions. Must add port to sources and targets of an edge")

                    this.childrenWithoutPortArray.push([cellObj, subNode]);
                    continue;
                }
                this.fillPorts(subNode, cellObj.port_directions, (p) => {
                    return p;
                }, cellObj);
            }
        }
    }

    fillEdges(node) {

        let edgeTargetsDict = {};
        let edgeSourcesDict = {};
        let constNodeDict = {};
        let [edgeDict, edgeArray] = this.getEdgeDictFromPorts(
            node, constNodeDict, edgeTargetsDict, edgeSourcesDict);
        let netnamesDict = getNetNamesDict(this.yosysModule);

        function getPortName(bit) {
            return netnamesDict[bit];
        }

        for (let i = 0; i < node.children.length; i++) {
            const subNode = node.children[i];
            if (constNodeDict[subNode.id] === 1) {
                //skip constants to iterate original cells
                continue;
            }

            let cell = this.nodeIdToCell[subNode.id];
            if (cell.port_directions === undefined) {
                continue;
            }
            let connections = cell.connections;
            let portDirections = cell.port_directions;


            if (connections === undefined) {
                throw new Error("Cannot find cell for subNode" + subNode.hwMeta.name);
            }

            let portI = 0;
            let portByName = this.nodePortNames[subNode.id];
            for (const [portName, bits] of Object.entries(connections)) {
                let portObj;
                let direction;
                if (portName.startsWith("$")) {
                    portObj = subNode.ports[portI++]
                    direction = portObj.direction.toLowerCase(); //use direction from module port definition
                } else {
                    portObj = portByName[portName];
                    if (portObj === undefined) {
                        console.error(`DEBUG: portByName[${portName}] is undefined for subNode ${subNode.hwMeta.name}, cell type=${cell.type}`);
                        console.error(`DEBUG: portByName keys: ${Object.keys(portByName || {}).join(', ')}`);
                        console.error(`DEBUG: connections keys: ${Object.keys(connections).join(', ')}`);
                    }
                    direction = portDirections[portName];
                }

                this.loadNets(node, subNode.id, portObj.id, bits, direction, edgeDict, constNodeDict,
                    edgeArray, getPortName, getSourceAndTargetForCell, edgeTargetsDict, edgeSourcesDict);

            }
        }
        // source null target null == direction is output

        for (const [cellObj, subNode] of this.childrenWithoutPortArray) {
            for (const [portName, bits] of Object.entries(cellObj.connections)) {
                let port = null;
                for (const bit of bits) {
                    let edge = edgeDict[bit];
                    if (edge === undefined) {
                        throw new Error("[Todo] create edge");
                    }
                    let edgePoints;
                    let direction;
                    if (edge.sources.length === 0 && edge.targets.length === 0) {
                        direction = "output";
                        edgePoints = edge.sources;
                    } else if (edge.sources.length === 0) {
                        // no sources -> add as source
                        direction = "output";
                        edgePoints = edge.sources;
                    } else {
                        direction = "input";
                        edgePoints = edge.targets;
                    }

                    if (port === null) {
                        let portByName = this.nodePortNames[subNode.id];
                        if (portByName === undefined) {
                            portByName = {};
                            this.nodePortNames[subNode.id] = portByName;
                        }
                        port = this.makeLPort(subNode.ports, portByName, portName, portName, direction, subNode.hwMeta.name);
                    }

                    edgePoints.push([subNode.id, port.id]);
                }
            }

        }

        let edgeSet = {}; // [sources, targets]: true
        for (const edge of edgeArray) {
            let key = [edge.sources, null, edge.targets]
            if (!edgeSet[key]) // filter duplicities
            {
                edgeSet[key] = true;
                node.edges.push(edge);
            }
        }

    }

    getEdgeDictFromPorts(node, constNodeDict, edgeTargetsDict, edgeSourcesDict) {
        let edgeDict = {}; // yosys bits (netId): LEdge
        let edgeArray = [];
        let portsIndex = 0;
        for (const [portName, portObj] of Object.entries(this.yosysModule.ports)) {
            let port = node.ports[portsIndex];
            portsIndex++;

            function getPortName2() {
                return portName;
            }

            this.loadNets(node, node.id, port.id, portObj.bits, portObj.direction,
                edgeDict, constNodeDict, edgeArray, getPortName2, getSourceAndTarget2,
                edgeTargetsDict, edgeSourcesDict)

        }
        return [edgeDict, edgeArray];
    }

    /*
     * Iterate bits representing yosys net names, which are used to get edges from the edgeDict.
     * If edges are not present in the dictionary, they are created and inserted into it. Eventually,
     * nodes are completed by filling sources and targets properties of LEdge.
     */
    loadNets(node, nodeId, portId, bits, direction, edgeDict, constNodeDict, edgeArray,
             getPortName, getSourceAndTarget, edgeTargetsDict, edgeSourcesDict) {
        for (let i = 0; i < bits.length; ++i) {
            let startIndex = i;
            let width = 1;
            let bit = bits[i];
            let portName = getPortName(bit);
            let edge = edgeDict[bit];
            let netIsConst = isConst(bit);
            if (netIsConst || edge === undefined) {
                // create edge if it is not in edgeDict
                if (portName === undefined) {
                    if (!netIsConst) {
                        throw new Error("Netname is undefined");
                    }
                    portName = bit;
                }
                edge = this.makeLEdge(portName);
                edgeDict[bit] = edge;
                edgeArray.push(edge);
                if (netIsConst) {
                    i = this.addConstNodeToSources(node, bits, edge.sources, i, constNodeDict);
                    width = i - startIndex + 1;
                }
            }

            let [a, b, targetA, targetB] = getSourceAndTarget(edge);
            if (direction === "input") {
                a.push([nodeId, portId]);
                if (targetA) {
                    addEdge(edge, portId, edgeTargetsDict, startIndex, width);
                } else {
                    addEdge(edge, portId, edgeSourcesDict, startIndex, width)
                }
            } else if (direction === "output") {
                b.push([nodeId, portId]);
                if (targetB) {
                    addEdge(edge, portId, edgeTargetsDict, startIndex, width);
                } else {
                    addEdge(edge, portId, edgeSourcesDict, startIndex, width);
                }
            } else {
                throw new Error("Unknown direction " + direction);
            }
        }
    }

    makeLEdge(name) {
        if (name === undefined) {
            throw new Error("Name is undefined");
        }
        let edge = {
            "id": this.idCounter.toString(),
            "sources": [],
            "targets": [], // [id of LNode, id of LPort]
            "hwMeta": { // [d3-hwschematic specific]
                "name": name, // optional string, displayed on mouse over
            }
        };
        ++this.idCounter;
        return edge;
    }

    addConstNodeToSources(node, bits, sources, i, constNodeDict) {
        let nameArray = [];
        for (i; i < bits.length; ++i) {
            let bit = bits[i];
            if (isConst(bit)) {
                nameArray.push(bit);
            } else {
                break;
            }
        }
        --i;
        // If bit is a constant, create a node with constant
        let nodeName = getConstNodeName(nameArray);
        let constSubNode;
        let port;
        [constSubNode, port] = this.addConstNode(node, nodeName, constNodeDict);
        sources.push([constSubNode.id, port.id]);
        return i;
    }

    addConstNode(node, nodeName, constNodeDict) {
        let port;

        let nodeBuilder = new LNodeMaker(nodeName, undefined, this.idCounter, null,
            this.hierarchyLevel + 1, this.nodePortNames);
        let subNode = nodeBuilder.make();
        this.idCounter = nodeBuilder.idCounter;

        let portByName = this.nodePortNames[subNode.id] = {};
        port = this.makeLPort(subNode.ports, portByName, "O0", "O0", "output", subNode.hwMeta.name);
        node.children.push(subNode);
        constNodeDict[subNode.id] = 1;

        return [subNode, port];
    }


}

export function yosys(yosysJson) {
    let nodePortNames = {};
    let rootNodeBuilder = new LNodeMaker("root", null, 0, null, 0, nodePortNames);
    let output = rootNodeBuilder.make();
    let topModuleName = getTopModuleName(yosysJson);

    let nodeBuilder = new LNodeMaker(topModuleName, yosysJson.modules[topModuleName], rootNodeBuilder.idCounter,
        yosysJson.modules, 1, nodePortNames);
    let node = nodeBuilder.make();
    output.children.push(node);
    output.hwMeta.maxId = nodeBuilder.idCounter - 1;
    //yosysTranslateIcons(output);
    //print output to console
    //console.log(JSON.stringify(output, null, 2));

    return output;
}
