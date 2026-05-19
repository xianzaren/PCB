# SmartPCB Reflow AI Code Final

## Project
AI-Based Quality Prediction and Predictive Maintenance for Smartphone PCB Assembly

## Required Tools
Before running the code, make sure you have:
- MATLAB
- Simulink
- Statistics and Machine Learning Toolbox


## Step-by-Step Run Order
Please run the scripts in MATLAB in this order.
---
## Step 1: Create the Simulink Model
Run: create00_reflow_oven_simulink_model_FIXED
This script will:
- Create the Simulink model
- Generate synthetic input sensor signals
- Save the Simulink model as:

## Step 2: Generate Sensor Data and Features
Run: generate01_sensor_data_from_simulink_FIXED
This script will:
- Run the Simulink model
- Extract simulated sensor signals
- Convert sensor signals into features
- Generate synthetic risk labels
- Save dataset files and plots in the `outputs` folder

Main outputs include:
```text
outputs/sensor_features_with_labels_FIXED.csv
outputs/temperature_tracking_FIXED.png
outputs/sensor_trends_FIXED.png
```

## Step 3: Train and Compare AI Models
Run:train02_ai_risk_models_FIXED
This script will:
- Train and compare machine learning models
- Select the best model for risk prediction
- Save trained models and evaluation results

Main outputs include:
```text
outputs/trained_risk_models_FIXED.mat
outputs/quality_model_comparison_FIXED.csv
outputs/maintenance_model_comparison_FIXED.csv
outputs/quality_confusion_FIXED.png
outputs/maintenance_confusion_FIXED.png
```

## Step 4: Run Prediction Demo
Run:run03_ai_prediction_demo_FIXED
This script will:
- Load the trained models
- Run example risk predictions
- Print predicted quality risk and maintenance risk
- Show possible causes and recommended actions

## Step 5: Open Dashboard
Run:run04_dashboard
This script will open an interactive dashboard.

The dashboard can:
- Use manual single-row input
- Use CSV stream input
- Show risk level
- Show warning lamps
- Show risk scores
- Show possible causes
- Show maintenance actions
- Save prediction history


## Recommended Full Run Order
Run all scripts in this order:
create00_reflow_oven_simulink_model_FIXED
generate01_sensor_data_from_simulink_FIXED
train02_ai_risk_models_FIXED
run03_ai_prediction_demo_FIXED
run041_dashboard


## Important Note
This project uses scenario-based synthetic sensor data.
It is only a proof-of-concept demo. It is not ready for real industrial deployment without real SMT sensor data, defect records, and maintenance records.