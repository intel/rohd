---
layout: splash
permalink: /
header:
  overlay_color: "#5e616c"
  overlay_image: /assets/images/mm-home-page-feature.jpg
  actions:
    - label: "<i class='fas fa-download'></i> Install now"
      url: "/get-started/setup/"
excerpt: >
  The Rapid Open Hardware Development (ROHD) framework is a framework for describing and verifying hardware in the Dart programming language. ROHD enables you to build and traverse a graph of connectivity between module objects using unrestricted software. <br />
  <small><a href="https://github.com/intel/rohd/releases">Latest release v0.4.1</a></small>
feature_row:
  - image_path: /assets/images/mm-customizable-feature.png
    alt: "Flexible Development"
    title: "Flexible Development"
    excerpt: "The development allows run-time dynamic module port definitions (numbers, names, widths, etc.) and internal module logic, including recursive module contents. Conversion of modules to equivalent, human-readable, structurally similar SystemVerilog for integration or downstream tool consumption"
    
  - image_path: /assets/images/mm-responsive-feature.png
    alt: "Modern Language"
    title: "Modern Language"
    excerpt: "Dart programming language enable fewer line of code in hardware design and verification. Modern IDE like VSCode also provides excellent static analysis, autocomplete, debugger, git, lint and etc which enables quality development."

  - image_path: /assets/images/mm-free-feature.png
    alt: "Open Source Project"
    title: "Open Source Project"
    excerpt: "ROHD is simple and fast, with no cumbersome build systems or EDA vendor tools. Open source community is established, allowing developers to contribute or extend the framework while obtaining assistance from the community world wide."
      
feature_row2:
  - image_path: /assets/images/abstract_layer.jpg
    alt: "Abstraction"
    title: "Develop and construct hardware design using ROHD in layer of abstraction"
    excerpt: 'Develop layers of abstraction within a hardware design, making it more flexible and powerful. Easy IP integration and interfaces; using an IP is as easy as an import. Reduces tedious, redundant, and error prone aspects of integration.'

feature_row3:
  - image_path: /assets/images/program.jpg
    alt: "placeholder image 2"
    title: "Unit Testing of the hardware design is fast, reliable, and easy to implement"
    excerpt: 'Validation collateral simpler to develop and debug. The ROHD Verification Framework helps build well-structured testbenches which provides excellent, simple, and fast unit-testing.'
---

<!-- Unsplash Image Source: https://unsplash.com/photos/FVgECvTjlBQ, https://unsplash.com/photos/KuCGlBXjH_o -->

{% include feature_row %}

{% include feature_row id="feature_row2" type="left" %}

{% include feature_row id="feature_row3" type="right" %}
