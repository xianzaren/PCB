# SmartPCB Reflow AI Code Final

## Project
AI-Based Quality Prediction and Predictive Maintenance for Smartphone PCB Assembly

## Required tools
- MATLAB
- Simulink
- Statistics and Machine Learning Toolbox

## Run order
Run these scripts in MATLAB in this order:

```matlab
create00_reflow_oven_simulink_model_FIXED
generate01_sensor_data_from_simulink_FIXED
train02_ai_risk_models_FIXED
run03_ai_prediction_demo_FIXED
run04_dashboard_sxy_version
```

## What each script does

1. `create00_reflow_oven_simulink_model_FIXED.m`
   - Creates the Simulink model.
   - Generates synthetic input signals.
   - Saves `SmartPCB_Reflow_AI_Model_FIXED.slx`.

2. `generate01_sensor_data_from_simulink_FIXED.m`
   - Runs the Simulink model.
   - Extracts simulated sensor signals.
   - Creates feature data and synthetic risk labels.
   - Saves plots and dataset files in `outputs`.

3. `train02_ai_risk_models_FIXED.m`
   - Trains Decision Tree models for quality risk and maintenance risk.
   - Saves confusion matrices and trained models.

4. `run03_ai_prediction_demo_FIXED.m`
   - Runs one example risk prediction.
   - Prints recommended engineering actions.

## Important note
The dataset is scenario-based synthetic sensor data. It is used for a proof-of-concept demo, not for real industrial deployment.
