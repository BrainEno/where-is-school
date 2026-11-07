# Playthrough screenshots

Captured by `tests/capture_playthrough.gd` in a real Godot window under
Xvfb (`--rendering-driver opengl3`, 1600x900). Interaction, dialogue
advance, choice selection and the language switch were produced with
simulated key events; walking between scenes was shortened with
teleports so the capture fits in CI. Regenerate with the
`Playthrough capture` workflow.

## 01_opening_line

The first line of the opening conversation, in English.

![01_opening_line](01_opening_line.png)

## 02_walking

The player after holding the forward key.

![02_walking](02_walking.png)

## 03_world_after_opening

The classroom with control returned and the objective set.

![03_world_after_opening](03_world_after_opening.png)

## 04_prompt_schoolbag

The interaction prompt with the key that is bound in the input map.

![04_prompt_schoolbag](04_prompt_schoolbag.png)

## 05_inspection_text

The schoolbag description, reached by pressing E.

![05_inspection_text](05_inspection_text.png)

## 06_chinese_world

The same classroom after switching to simplified Chinese at runtime.

![06_chinese_world](06_chinese_world.png)

## 07_prompt_chinese

The interaction prompt after the switch

![07_prompt_chinese](07_prompt_chinese.png)

## 08_repeat_read_chinese

The second read of the same object, in Chinese.

![08_repeat_read_chinese](08_repeat_read_chinese.png)

## 09_prompt_talk_chinese

The prompt for a conversation, in Chinese.

![09_prompt_talk_chinese](09_prompt_talk_chinese.png)

## 10_conversation_chinese

A conversation line in Chinese, opened with E.

![10_conversation_chinese](10_conversation_chinese.png)

## 11_back_to_english

The same scene after switching back to English.

![11_back_to_english](11_back_to_english.png)

## 12_door_prompt

The classroom door is open

![12_door_prompt](12_door_prompt.png)

## 13_corridor

The walkway outside the classroom.

![13_corridor](13_corridor.png)

## 14_street

The street outside the school gate, with the arrival line finished.

![14_street](14_street.png)

## 15_street_prompt

A street object with its prompt.

![15_street_prompt](15_street_prompt.png)

## 16_street_inspection

The street object's description.

![16_street_inspection](16_street_inspection.png)

## 15b_stair_prompt

The way up to the residential area.

![15b_stair_prompt](15b_stair_prompt.png)

## 17_residential

The courtyard behind the school

![17_residential](17_residential.png)

## FAIL_animal_prompt

No prompt appeared for the animal.

![FAIL_animal_prompt](FAIL_animal_prompt.png)

## 18_animal_prompt

The green animal, with the prompt to look at it.

![18_animal_prompt](18_animal_prompt.png)

## 19_animal_conversation

Meeting the animal

![19_animal_conversation](19_animal_conversation.png)

## 20_end_card

The end-of-slice card at the end of the built content.

![20_end_card](20_end_card.png)

## FAIL_last_frame

The last frame before the capture stopped.

![FAIL_last_frame](FAIL_last_frame.png)

