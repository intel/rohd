---
layout: splash
permalink: /
hidden: true
header:
  overlay_color: "#5e616c"
  overlay_image: /assets/images/mm-home-page-feature.jpg
  actions:
    - label: "<i class='fas fa-download'></i> Install now"
      url: "/get-started/setup/"
excerpt: >
  Develop and design Hardware seamlessly with the power of ROHD.<br />
  <small><a href="https://github.com/intel/rohd/releases">Latest release v0.4.0</a></small>
feature_row:
  - image_path: /assets/images/mm-customizable-feature.png
    alt: "Flexible Development"
    title: "Flexible Development"
    excerpt: "The development allows run-time dynamic module port definitions (numbers, names, widths, etc.) and internal module logic, including recursive module contents. Conversion of modules to equivalent, human-readable, structurally similar SystemVerilog for integration or downstream tool consumption"
    # url: "/docs/configuration/"
    # btn_class: "btn--primary"
    # btn_label: "Learn more"
  - image_path: /assets/images/mm-responsive-feature.png
    alt: "Modern Language"
    title: "Modern Language"
    excerpt: "Dart programming language enable fewer line of code in hardware design and verification. Modern IDE like VSCode also provides excellent static analysis, autocomplete, debugger, git, lint and etc which enables quality development."
    # url: "/docs/layouts/"
    # btn_class: "btn--primary"
    # btn_label: "Learn more"

  - image_path: /assets/images/mm-free-feature.png
    alt: "Open Source Project"
    title: "Open Source Project"
    excerpt: "ROHD is simple and fast, with no cumbersome build systems or EDA vendor tools. Open source community is established, allowing developers to contribute or extend the framework while obtaining assistance from the community world wide."
    # url: "/docs/license/"
    # btn_class: "btn--primary"
    # btn_label: "Learn more"
      
feature_row2:
  - image_path: /assets/images/unsplash-gallery-image-2-th.jpg
    alt: "Abstraction"
    title: "Develop and construct hardware design using ROHD in layer of abstraction"
    excerpt: 'Develop layers of abstraction within a hardware design, making it more flexible and powerful. Easy IP integration and interfaces; using an IP is as easy as an import. Reduces tedious, redundant, and error prone aspects of integration.'
    # url: "#test-link"
    # btn_label: "Read More"
    # btn_class: "btn--primary"    

feature_row3:
  - image_path: /assets/images/unsplash-gallery-image-2-th.jpg
    alt: "placeholder image 2"
    title: "Unit Testing of the hardware design is fast, reliable, and easy to implement"
    excerpt: 'Validation collateral simpler to develop and debug. The ROHD Verification Framework helps build well-structured testbenches which provides excellent, simple, and fast unit-testing.'
    # url: "#test-link"
    # btn_label: "Read More"
    # btn_class: "btn--primary"
---

{% include feature_row %}

{% include feature_row id="feature_row2" type="left" %}

{% include feature_row id="feature_row3" type="right" %}
