#!/bin/bash
set -e

# Release PR Action Script
# Usage: release-pr.sh <pr-title> <production-branch> <staging-branch> <labels>

# Assign input parameters
PR_TITLE="$1"
PRODUCTION_BRANCH="$2"
STAGING_BRANCH="$3"
LABELS="$4"

log() {
    echo "$1"
}

check_existing_pr() {
    local production_branch="$1"
    local staging_branch="$2"
    
    gh pr list --base "$production_branch" --head "$staging_branch" --json number --jq '.[0].number' || echo ""
}

generate_pr_description() {
    local production_branch="$1"
    local staging_branch="$2"
    
    git log origin/$production_branch..origin/$staging_branch --pretty=format:"%s" \
      | grep -oP '#\K[0-9]+' \
      | xargs -I {} gh pr view {} \
          --json number,author \
          --jq '"- [ ] #\(.number) by @\(.author.login)"' \
      > release_prs.txt || true
    
    cat > pr_body.txt << 'EOF'
## Release PR

### Changes included in this release:

EOF
    
    if [ -s release_prs.txt ]; then
        cat release_prs.txt >> pr_body.txt
        return 0
    else
        echo "No PRs found in this release." >> pr_body.txt
        return 1
    fi
}

parse_labels() {
    local labels="$1"
    local label_flags=""
    
    IFS=',' read -ra label_array <<< "$labels"
    for label in "${label_array[@]}"; do
        label=$(echo "$label" | xargs)
        [ -n "$label" ] && label_flags="$label_flags --label $label"
    done
    
    echo "$label_flags"
}

create_new_pr() {
    local pr_title="$1"
    local production_branch="$2"
    local staging_branch="$3"
    local label_flags="$4"
    
    gh pr create \
      --title "$pr_title" \
      --body-file pr_body.txt \
      --base "$production_branch" \
      --head "$staging_branch" \
      $label_flags
}

update_existing_pr() {
    local pr_number="$1"
    
    gh pr edit "$pr_number" --body-file pr_body.txt
}

# Main execution flow
log "Starting release PR workflow..."

# Check for existing PR
PR_NUMBER=$(check_existing_pr "$PRODUCTION_BRANCH" "$STAGING_BRANCH")

if [ -n "$PR_NUMBER" ]; then
    PR_EXISTS=true
    log "Found existing release PR: #$PR_NUMBER"
else
    PR_EXISTS=false
    log "No existing release PR"
fi

# Generate PR description
if generate_pr_description "$PRODUCTION_BRANCH" "$STAGING_BRANCH"; then
    PR_COUNT=$(wc -l < release_prs.txt)
    log "Generated description with $PR_COUNT PR(s)"
else
    log "No PRs to include"
fi

# Create or update PR
if [ "$PR_EXISTS" = false ]; then
    LABEL_FLAGS=$(parse_labels "$LABELS")
    create_new_pr "$PR_TITLE" "$PRODUCTION_BRANCH" "$STAGING_BRANCH" "$LABEL_FLAGS"
    PR_NUMBER=$(check_existing_pr "$PRODUCTION_BRANCH" "$STAGING_BRANCH")
    log "Created release PR #$PR_NUMBER"
else
    update_existing_pr "$PR_NUMBER"
    log "Updated release PR #$PR_NUMBER"
fi
