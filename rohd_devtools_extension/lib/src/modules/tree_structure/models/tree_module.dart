class TreeModel {
  final String name;
  final Map<String, dynamic> inputs;
  final Map<String, dynamic> outputs;
  final List<TreeModel> subModules;

  TreeModel({
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.subModules,
  });

  factory TreeModel.fromJson(Map<String, dynamic> json) {
    return TreeModel(
      name: json['name'],
      inputs: Map<String, dynamic>.from(json['inputs']),
      outputs: Map<String, dynamic>.from(json['outputs']),
      subModules: (json["subModules"] as List)
          .map((subModule) => TreeModel.fromJson(subModule))
          .toList(),
    );
  }
}
