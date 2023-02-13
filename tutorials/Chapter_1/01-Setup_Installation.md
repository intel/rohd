# ROHD Setup & Installation

There are two ways of development in ROHD. First, You can run ROHD on GitHub codespace or local machine. 


## Setup on Github Codespaces (Recommended)

1. To access the Codespaces feature on the https://github.com/intel/rohd repository, simply click on the "Codespaces" button. Keep in mind that Codespaces are available for free to everyone, however, there is a monthly usage limit. For more information, please visit the official GitHub Codespaces Overview page at https://docs.github.com/en/codespaces/overview.

> All personal GitHub.com accounts have a monthly quota of free use of GitHub Codespaces included in the Free or Pro plan. You can get started using GitHub Codespaces on your personal account without changing any settings or providing payment details. You can create and use a codespace for any repository you can clone. You can also use a template to create codespaces that are not initially associated with a repository. If you create a codespace from an organization-owned repository, use of the codespace will either be charged to the organization (if the organization is configured for this), or to your personal account. Codespaces created from templates are always charged to your personal account. You can continue using GitHub Codespaces beyond your monthly included storage and compute usage by providing payment details and setting a spending limit. For more information, see "About billing for GitHub Codespaces.

![step 1](assets/CodespaceSetup/step1.PNG)

2. You will be redirected to a page where GitHub will launch the container for you. Please be patient as GitHub sets up your server.

![step 2](assets/CodespaceSetup/step2.PNG)

3. When your space is ready, you will see a visual studio code running on your browser.

![step 3](assets/CodespaceSetup/step3.PNG)

4. Run `dart pub get` on the terminal of the visual studio code to pull your setup.

![step 4](assets/CodespaceSetup/step4.PNG)

5. Open up `example` folder on the left navigation panel and click on `example.dart` to bring forward the first example of ROHD. After that, navigate to the main function at below of line 58 and click on the `Run` at `Run | Debug`.

![step 5](assets/CodespaceSetup/step5.PNG)


If you can see SystemVerilog code pop up on the terminal. Well, you have successfully set up your development environment on the cloud.

6. To delete the codespace, go back to https://github.com/intel/rohd and click on codespace just like step 1. But this time, you will see more options. Click on the `delete` option to delete codespace.

![step 6](assets/CodespaceSetup/step6.PNG)


## Local Development Setup

Pre-requiresite:

- Install latest `dart` SDK from official dart website: 

https://dart.dev/get-dart

- Install Visual Studio Code

https://code.visualstudio.com/Download

1. Clone the repository to the local directory. On your terminal, run 

```cmd
$ git clone https://github.com/intel/rohd.git
```

2. Open up your repository in VSCode using the command

```cmd
$ code rohd
```

You will see vscode automatically open up your ROHD folder. 

![step 2](assets/localSetup/step2.PNG)

3. Open up terminal in your VSCode by go to view -> terminal. Then, get the rohd package downloaded using the command below.

```cmd
$ dart pub get
```

4. Open up `example` folder on the left navigation panel and click on `example.dart` to bring forward the first example of ROHD. After that, navigate to the main function at below of line 58 and click on the `Run` at `Run | Debug`.

![step 4](assets/localSetup/step4.PNG)

If you can see SystemVerilog code pop up on the terminal. Congratulation, you now are ready to go with ROHD development.

----------------
2023 February 13
Author: Yao Jing Quek <<yao.jing.quek@intel.com>>

 
Copyright (C) 2021-2023 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause