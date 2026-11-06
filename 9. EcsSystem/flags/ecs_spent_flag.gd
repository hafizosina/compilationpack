class_name EcsSpentFlag
extends EcsFlag

## A bar of it was spent on since EcsSkillCostSystem last ran, so systems that visit only
## what changed (health) apply it. Raised and cleared by EcsSkillCostSystem.
