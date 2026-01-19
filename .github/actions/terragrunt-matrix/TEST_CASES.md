# Terragrunt Matrix Action - Test Cases

This document describes test cases for the parent-grouping feature.

## Test Directory Structures

### Test Case 1: Simple Flat Structure (Legacy Mode)

**Directory Structure:**
```
accounts/
├── us-east-1/
│   ├── prod/
│   │   └── terragrunt.hcl
│   └── dev/
│       └── terragrunt.hcl
└── us-west-2/
    ├── prod/
    │   └── terragrunt.hcl
    └── dev/
        └── terragrunt.hcl
```

**Input:**
- `group-by-parent: false`

**Expected Output (Legacy Mode):**
```json
{
  "unit": [
    {
      "file": "accounts/us-east-1/prod/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-east-1",
      "account": "prod"
    },
    {
      "file": "accounts/us-east-1/dev/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "us-east-1",
      "account": "dev"
    },
    {
      "file": "accounts/us-west-2/prod/terragrunt.hcl",
      "relative_path": "accounts/us-west-2/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-west-2",
      "account": "prod"
    },
    {
      "file": "accounts/us-west-2/dev/terragrunt.hcl",
      "relative_path": "accounts/us-west-2/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "us-west-2",
      "account": "dev"
    }
  ]
}
```

**Matrix Count:** 4

---

### Test Case 2: Flat with Nested Modules (Parent-Grouping Mode)

**Directory Structure:**
```
accounts/
├── us-east-1/
│   ├── prod/
│   │   ├── terragrunt.hcl
│   │   ├── vpc/
│   │   │   └── terragrunt.hcl
│   │   └── eks/
│   │       └── terragrunt.hcl
│   └── dev/
│       ├── terragrunt.hcl
│       └── vpc/
│           └── terragrunt.hcl
└── us-west-2/
    └── prod/
        ├── terragrunt.hcl
        └── networking/
            └── terragrunt.hcl
```

**Input:**
- `group-by-parent: true`
- `parent-pattern: "accounts/[^/]+/[^/]+"`

**Expected Output (Parent-Grouping Mode):**
```json
{
  "unit": [
    {
      "file": "accounts/us-east-1/prod/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-east-1",
      "account": "prod",
      "modules": ["vpc", "eks"],
      "module_count": 2
    },
    {
      "file": "accounts/us-east-1/dev/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "us-east-1",
      "account": "dev",
      "modules": ["vpc"],
      "module_count": 1
    },
    {
      "file": "accounts/us-west-2/prod/terragrunt.hcl",
      "relative_path": "accounts/us-west-2/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-west-2",
      "account": "prod",
      "modules": ["networking"],
      "module_count": 1
    }
  ]
}
```

**Matrix Count:** 3

---

### Test Case 3: Parent Without Children

**Directory Structure:**
```
accounts/
├── us-east-1/
│   └── prod/
│       └── terragrunt.hcl
└── us-west-2/
    └── staging/
        ├── terragrunt.hcl
        └── database/
            └── terragrunt.hcl
```

**Input:**
- `group-by-parent: true`
- `parent-pattern: "accounts/[^/]+/[^/]+"`

**Expected Output:**
```json
{
  "unit": [
    {
      "file": "accounts/us-east-1/prod/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-east-1",
      "account": "prod",
      "modules": [],
      "module_count": 0
    },
    {
      "file": "accounts/us-west-2/staging/terragrunt.hcl",
      "relative_path": "accounts/us-west-2/staging/terragrunt.hcl",
      "unit_name": "staging",
      "region": "us-west-2",
      "account": "staging",
      "modules": ["database"],
      "module_count": 1
    }
  ]
}
```

**Matrix Count:** 2

---

### Test Case 4: Deep Nested Modules

**Directory Structure:**
```
accounts/
└── us-east-1/
    └── prod/
        ├── terragrunt.hcl
        ├── networking/
        │   └── terragrunt.hcl
        ├── compute/
        │   ├── terragrunt.hcl
        │   └── autoscaling/
        │       └── terragrunt.hcl
        └── storage/
            └── terragrunt.hcl
```

**Input:**
- `group-by-parent: true`
- `parent-pattern: "accounts/[^/]+/[^/]+"`

**Expected Output:**
```json
{
  "unit": [
    {
      "file": "accounts/us-east-1/prod/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-east-1",
      "account": "prod",
      "modules": ["networking", "compute", "storage"],
      "module_count": 3
    }
  ]
}
```

**Notes:**
- `compute/autoscaling/terragrunt.hcl` is treated as a child of `compute`, which is a module of the parent
- All modules at any depth under the parent are collected

**Matrix Count:** 1

---

### Test Case 5: Excluded Patterns

**Directory Structure:**
```
accounts/
├── us-east-1/
│   ├── prod/
│   │   ├── terragrunt.hcl
│   │   ├── vpc/
│   │   │   └── terragrunt.hcl
│   │   └── .terragrunt-cache/
│   │       └── terragrunt.hcl (should be excluded)
│   └── dev/
│       └── terragrunt.hcl
└── node_modules/  (should be excluded)
    └── accounts/
        └── us-west-2/
            └── prod/
                └── terragrunt.hcl
```

**Input:**
- `group-by-parent: true`
- `exclude-patterns: ".terragrunt-cache,node_modules,.git"`
- `parent-pattern: "accounts/[^/]+/[^/]+"`

**Expected Output:**
```json
{
  "unit": [
    {
      "file": "accounts/us-east-1/prod/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-east-1",
      "account": "prod",
      "modules": ["vpc"],
      "module_count": 1
    },
    {
      "file": "accounts/us-east-1/dev/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "us-east-1",
      "account": "dev",
      "modules": [],
      "module_count": 0
    }
  ]
}
```

**Matrix Count:** 2

---

### Test Case 6: Multiple Regions and Accounts

**Directory Structure:**
```
accounts/
├── us-east-1/
│   ├── prod/
│   │   ├── terragrunt.hcl
│   │   ├── vpc/
│   │   │   └── terragrunt.hcl
│   │   └── eks/
│   │       └── terragrunt.hcl
│   ├── staging/
│   │   ├── terragrunt.hcl
│   │   └── vpc/
│   │       └── terragrunt.hcl
│   └── dev/
│       └── terragrunt.hcl
├── us-west-2/
│   ├── prod/
│   │   ├── terragrunt.hcl
│   │   └── networking/
│   │       └── terragrunt.hcl
│   └── dev/
│       └── terragrunt.hcl
└── eu-west-1/
    ├── prod/
    │   ├── terragrunt.hcl
    │   ├── vpc/
    │   │   └── terragrunt.hcl
    │   └── database/
    │       └── terragrunt.hcl
    └── dev/
        └── terragrunt.hcl
```

**Input:**
- `group-by-parent: true`
- `parent-pattern: "accounts/[^/]+/[^/]+"`

**Expected Output:**
```json
{
  "unit": [
    {
      "file": "accounts/us-east-1/prod/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-east-1",
      "account": "prod",
      "modules": ["vpc", "eks"],
      "module_count": 2
    },
    {
      "file": "accounts/us-east-1/staging/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/staging/terragrunt.hcl",
      "unit_name": "staging",
      "region": "us-east-1",
      "account": "staging",
      "modules": ["vpc"],
      "module_count": 1
    },
    {
      "file": "accounts/us-east-1/dev/terragrunt.hcl",
      "relative_path": "accounts/us-east-1/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "us-east-1",
      "account": "dev",
      "modules": [],
      "module_count": 0
    },
    {
      "file": "accounts/us-west-2/prod/terragrunt.hcl",
      "relative_path": "accounts/us-west-2/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-west-2",
      "account": "prod",
      "modules": ["networking"],
      "module_count": 1
    },
    {
      "file": "accounts/us-west-2/dev/terragrunt.hcl",
      "relative_path": "accounts/us-west-2/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "us-west-2",
      "account": "dev",
      "modules": [],
      "module_count": 0
    },
    {
      "file": "accounts/eu-west-1/prod/terragrunt.hcl",
      "relative_path": "accounts/eu-west-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "eu-west-1",
      "account": "prod",
      "modules": ["vpc", "database"],
      "module_count": 2
    },
    {
      "file": "accounts/eu-west-1/dev/terragrunt.hcl",
      "relative_path": "accounts/eu-west-1/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "eu-west-1",
      "account": "dev",
      "modules": [],
      "module_count": 0
    }
  ]
}
```

**Matrix Count:** 7

---

## Console Output Examples

### Parent-Grouping Mode

```
Searching for Terragrunt units in: .
Looking for files: terragrunt.hcl
Excluding patterns: .terragrunt-cache,node_modules,.git

Found parent unit: prod (accounts/us-east-1/prod/terragrunt.hcl) with 2 module(s)
  Modules: vpc,eks
Found parent unit: dev (accounts/us-east-1/dev/terragrunt.hcl) with 1 module(s)
  Modules: vpc
Found parent unit: prod (accounts/us-west-2/prod/terragrunt.hcl) with 1 module(s)
  Modules: networking

Matrix generated:
{
  "unit": [
    {...},
    {...},
    {...}
  ]
}

Found 3 Terragrunt units
Units: prod,dev,prod
```

### Legacy Mode

```
Searching for Terragrunt units in: .
Looking for files: terragrunt.hcl
Excluding patterns: .terragrunt-cache,node_modules,.git

Found unit: prod (accounts/us-east-1/prod/terragrunt.hcl)
Found unit: vpc (accounts/us-east-1/prod/vpc/terragrunt.hcl)
Found unit: eks (accounts/us-east-1/prod/eks/terragrunt.hcl)
Found unit: dev (accounts/us-east-1/dev/terragrunt.hcl)
Found unit: vpc (accounts/us-east-1/dev/vpc/terragrunt.hcl)
Found unit: prod (accounts/us-west-2/prod/terragrunt.hcl)
Found unit: networking (accounts/us-west-2/prod/networking/terragrunt.hcl)

Matrix generated:
{
  "unit": [
    {...},
    {...},
    {...},
    {...},
    {...},
    {...},
    {...}
  ]
}

Found 7 Terragrunt units
Units: prod,vpc,eks,dev,vpc,prod,networking
```

---

## How to Run Tests Manually

### Setup Test Environment

```bash
#!/bin/bash

# Create test directory structure
mkdir -p test-cases/case2/{accounts/{us-east-1,us-west-2}/{prod,dev},{accounts/us-east-1/prod/{vpc,eks},accounts/us-east-1/dev/vpc,accounts/us-west-2/prod/networking}}

# Create dummy terragrunt.hcl files
find test-cases/case2 -type d -name "prod" -o -name "dev" | while read dir; do
  touch "$dir/terragrunt.hcl"
  mkdir -p "$dir/vpc" "$dir/eks" "$dir/networking" 2>/dev/null || true
  touch "$dir/vpc/terragrunt.hcl" 2>/dev/null || true
  touch "$dir/eks/terragrunt.hcl" 2>/dev/null || true
  touch "$dir/networking/terragrunt.hcl" 2>/dev/null || true
done
```

### Run Parent-Grouping Mode

```bash
cd test-cases/case2
/path/to/action/script.sh \
  --terragrunt-dir . \
  --group-by-parent true \
  --parent-pattern "accounts/[^/]+/[^/]+"
```

### Run Legacy Mode

```bash
cd test-cases/case2
/path/to/action/script.sh \
  --terragrunt-dir . \
  --group-by-parent false
```

---

## Validation Checklist

- [ ] Parent units are correctly identified using `parent-pattern`
- [ ] Child modules are grouped under their parent
- [ ] `module_count` matches the number of modules in the `modules` array
- [ ] All excluded patterns are respected
- [ ] Region and account extraction works with nested modules
- [ ] Legacy mode still works when `group-by-parent: false`
- [ ] Matrix JSON is valid and properly formatted
- [ ] Console output clearly shows parent-to-children relationships
- [ ] Empty `modules` array for parents without children
- [ ] Multiple levels of nesting are handled correctly
