# Terragrunt Matrix Action - Parent-Grouping Feature Implementation

## Summary

The `terragrunt-matrix` action has been enhanced to support parent-level grouping of nested Terragrunt modules. This allows you to execute all modules under a parent unit (e.g., `accounts/REGION/ACCOUNT/`) in a single job using `terragrunt run-all`, rather than creating separate jobs for each module.

## Key Changes

### 1. New Inputs (action.yml)

```yaml
group-by-parent:
  description: "Group nested modules under parent unit (assumes parent-pattern structure)"
  required: false
  default: "true"

parent-pattern:
  description: "Regex pattern to identify parent units (relative path, e.g., 'accounts/[^/]+/[^/]+')"
  required: false
  default: "accounts/[^/]+/[^/]+"
```

### 2. Enhanced Matrix Object Fields

When `group-by-parent: true`, the matrix output includes:

```json
{
  "file": "accounts/us-east-1/prod/terragrunt.hcl",
  "relative_path": "accounts/us-east-1/prod/terragrunt.hcl",
  "unit_name": "prod",
  "region": "us-east-1",
  "account": "prod",
  "modules": ["vpc", "eks", "networking"],
  "module_count": 3
}
```

New fields:
- `modules[]`: Array of nested module names (e.g., `["vpc", "eks"]`)
- `module_count`: Count of nested modules

### 3. Behavior Changes

#### Parent-Grouping Mode (Default: `group-by-parent: true`)

- **Identifies parent units** by matching the `parent-pattern` regex
- **Groups child modules** under each parent
- **Returns one matrix entry per parent**, with all children metadata
- All modules under that parent can be deployed together with `terragrunt run-all`

Example structure:
```
accounts/us-east-1/prod/terragrunt.hcl         ← Parent unit
accounts/us-east-1/prod/vpc/terragrunt.hcl      ← Child module
accounts/us-east-1/prod/eks/terragrunt.hcl      ← Child module
```

Results in **1 matrix entry** with `module_count: 2` and `modules: ["vpc", "eks"]`

#### Legacy Mode (`group-by-parent: false`)

- Preserves original behavior
- Returns one matrix entry per `terragrunt.hcl` file
- No `modules` or `module_count` fields
- Useful for non-account-based structures or maximum parallelization

## How to Use

### Parent-Grouping Mode (Recommended)

```yaml
- uses: ./.github/actions/terragrunt-matrix
  id: matrix
  with:
    terragrunt-dir: "."
    group-by-parent: true
    parent-pattern: "accounts/[^/]+/[^/]+"

- name: Deploy Terragrunt
  matrix: ${{ fromJson(steps.matrix.outputs.matrix) }}
  run: |
    cd ${{ matrix.unit.file }}
    # This automatically includes all nested modules
    terragrunt run-all apply
```

### Legacy Mode (for backward compatibility)

```yaml
- uses: ./.github/actions/terragrunt-matrix
  id: matrix
  with:
    terragrunt-dir: "."
    group-by-parent: false
```

## Example Outputs

### Input Structure
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

### Parent-Grouping Output (3 jobs)
```json
{
  "unit": [
    {
      "file": "accounts/us-east-1/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-east-1",
      "account": "prod",
      "modules": ["vpc", "eks"],
      "module_count": 2
    },
    {
      "file": "accounts/us-east-1/dev/terragrunt.hcl",
      "unit_name": "dev",
      "region": "us-east-1",
      "account": "dev",
      "modules": ["vpc"],
      "module_count": 1
    },
    {
      "file": "accounts/us-west-2/prod/terragrunt.hcl",
      "unit_name": "prod",
      "region": "us-west-2",
      "account": "prod",
      "modules": ["networking"],
      "module_count": 1
    }
  ]
}
```

### Legacy Mode Output (7 jobs)
```json
{
  "unit": [
    {"file": "accounts/us-east-1/prod/terragrunt.hcl", "unit_name": "prod", ...},
    {"file": "accounts/us-east-1/prod/vpc/terragrunt.hcl", "unit_name": "vpc", ...},
    {"file": "accounts/us-east-1/prod/eks/terragrunt.hcl", "unit_name": "eks", ...},
    {"file": "accounts/us-east-1/dev/terragrunt.hcl", "unit_name": "dev", ...},
    {"file": "accounts/us-east-1/dev/vpc/terragrunt.hcl", "unit_name": "vpc", ...},
    {"file": "accounts/us-west-2/prod/terragrunt.hcl", "unit_name": "prod", ...},
    {"file": "accounts/us-west-2/prod/networking/terragrunt.hcl", "unit_name": "networking", ...}
  ]
}
```

## Benefits

- **Atomic deployments**: All modules in an account deploy together with shared state
- **Simplified job management**: Fewer jobs to manage and monitor
- **Cleaner workflows**: Respects logical unit boundaries
- **Backward compatible**: Legacy mode still works via `group-by-parent: false`

## Testing

See `TEST_CASES.md` for:
- 6 comprehensive test scenarios
- Expected outputs for each scenario
- Console output examples
- Manual testing instructions
- Validation checklist

## Files Modified

1. `.github/actions/terragrunt-matrix/action.yml`
   - Added `group-by-parent` and `parent-pattern` inputs
   - Enhanced bash script with parent-grouping logic
   - Maintained backward compatibility with legacy mode

2. `.github/actions/terragrunt-matrix/TEST_CASES.md` (new)
   - Complete test case documentation
   - Directory structures and expected outputs
   - Console output examples
   - Testing procedures

## Implementation Details

### Parent Detection Algorithm

1. **Find all terragrunt.hcl files**
2. **Classify each file**:
   - **Parent**: Matches `parent-pattern` (e.g., `accounts/[^/]+/[^/]+/terragrunt.hcl`)
   - **Child**: Located under a parent directory
   - **Orphaned**: No matching parent (logged as warning)
3. **Group children under parents**: Collect all child modules for each parent
4. **Build matrix**: Create one entry per parent with nested modules metadata

### Key Features

- **Duplicate prevention**: Module names are deduplicated (same module name under parent)
- **Deep nesting support**: Handles multiple levels of nesting (e.g., `module1/submodule/terragrunt.hcl`)
- **Flexible patterns**: Custom `parent-pattern` allows different directory structures
- **Backward compatible**: Legacy mode uses original single-file-per-job logic
