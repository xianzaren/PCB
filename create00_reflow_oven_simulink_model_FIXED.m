%% create00_reflow_oven_simulink_model_FIXED.m
% Creates a simplified Simulink model for smartphone PCB assembly:
% Reflow oven temperature control + scenario-based synthetic SMT sensor signals.
% Run this first.
%
% This model is a proof-of-concept demo:
% - The upper part represents reflow oven temperature control.
% - The lower part represents SMT line sensor monitoring.
% - The model can be explained as a supervisory monitoring layer for an
%   automated / robotic SMT assembly line, but it is not a robot motion controller.

clear; clc; close all;
rng(42);   % fixed random seed for reproducibility

%% Path setup
projectRoot = fileparts(mfilename('fullpath'));
if isempty(projectRoot)
    projectRoot = pwd;
end
cd(projectRoot);

outDir = fullfile(projectRoot, 'outputs');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% Model name
model = 'SmartPCB_Reflow_AI_Model_FIXED';

if bdIsLoaded(model)
    close_system(model, 0);
end

modelFile = fullfile(projectRoot, [model '.slx']);
if isfile(modelFile)
    delete(modelFile);
end

%% Create input time series for Simulink
% One simplified reflow cycle is 120 seconds.
% Twenty cycles are used to increase sample size for AI feature extraction.

cycleTime = 120;
numCycles = 20; 
t = (0:1:cycleTime*numCycles)';

% Simplified reflow-like target temperature profile for one cycle.
% In real production, the profile should be defined according to solder paste,
% PCB design, component thermal limits, and oven zone settings.
profileTime = [0 20 60 90 120]';
profileTemp = [30 150 230 100 60]';

% Repeat the profile for multiple cycles.
tCycle = mod(t, cycleTime);
tCycle(tCycle == 0 & t > 0) = cycleTime;

setpoint = interp1(profileTime, profileTemp, tCycle, 'linear');

%% Production-inspired thermal model assumptions
% The thermal plant represents temperature rise above ambient temperature.
% Actual temperature = thermal response + ambient temperature + sensor noise.
%
% This is still a simplified lumped first-order thermal model.
% In real industrial deployment, the gain and time constant should be identified
% from measured oven response data.

Tamb = 25;             % ambient temperature, degree C
TmaxApprox = 250;      % approximate maximum controlled oven temperature, degree C
heaterMax = 100;       % heater power percentage
thermalGain = (TmaxApprox - Tamb) / heaterMax;  % degree C rise per 1% heater power
thermalTau = 25;       % simplified thermal time constant, seconds

%% Scenario-based synthetic SMT line sensor signals
% These signals represent an automated SMT line around the reflow oven.
% They are generated with industrial scenario logic, not purely random labels.

conveyorSpeed = 0.85 + 0.02*sin(0.04*t);                         % m/min, simplified
motorCurrent  = 2.8 + 0.18*sin(0.03*t);                          % A, simplified
vibrationSig  = 0.18 + 0.025*sin(0.06*t) + 0.008*randn(size(t));  % arbitrary unit
operatingHours = 500 + 0.1*t;                                    % accumulated hours

% Cycle index for scenario assignment
cycleIdx = floor(t / cycleTime) + 1;
cycleIdx(cycleIdx > numCycles) = numCycles;

% Apply different production scenarios across cycles.
% This makes the synthetic data more meaningful for a proof-of-concept model.
for c = 1:numCycles
    idx = (cycleIdx == c);
    scenario = mod(c-1, 5) + 1;

    switch scenario
        case 1
            % Scenario 1: Normal operation
            % Stable conveyor, normal current, normal vibration.

        case 2
            % Scenario 2: Conveyor speed abnormality
            % Conveyor runs faster, so PCB heating time may be affected.
            conveyorSpeed(idx) = conveyorSpeed(idx) + 0.06;

        case 3
            % Scenario 3: Motor or fan degradation
            % Higher motor current and vibration indicate possible maintenance risk.
            motorCurrent(idx) = motorCurrent(idx) + 0.35;
            vibrationSig(idx) = vibrationSig(idx) + 0.07;

        case 4
            % Scenario 4: Heater ageing / high system effort
            % Higher current and vibration suggest the system is working harder.
            motorCurrent(idx) = motorCurrent(idx) + 0.20;
            vibrationSig(idx) = vibrationSig(idx) + 0.04;

        case 5
            % Scenario 5: Severe unstable process
            % Multiple sensor channels become abnormal.
            conveyorSpeed(idx) = conveyorSpeed(idx) - 0.05;
            motorCurrent(idx) = motorCurrent(idx) + 0.45;
            vibrationSig(idx) = vibrationSig(idx) + 0.09;
    end
end

% Keep signals within reasonable demonstration ranges.
conveyorSpeed = max(min(conveyorSpeed, 1.05), 0.65);
motorCurrent = max(motorCurrent, 0);
vibrationSig = max(vibrationSig, 0);

%% Create timeseries variables for From Workspace blocks

reflow_setpoint_ts = timeseries(setpoint, t);
conveyor_speed_ts = timeseries(conveyorSpeed, t);
motor_current_ts = timeseries(motorCurrent, t);
vibration_ts = timeseries(vibrationSig, t);
operating_hours_ts = timeseries(operatingHours, t);

%% Assign to base workspace for Simulink

assignin('base', 'reflow_setpoint_ts', reflow_setpoint_ts);
assignin('base', 'conveyor_speed_ts', conveyor_speed_ts);
assignin('base', 'motor_current_ts', motor_current_ts);
assignin('base', 'vibration_ts', vibration_ts);
assignin('base', 'operating_hours_ts', operating_hours_ts);

%% Save input signals for later scripts

save(fullfile(outDir, 'simulink_input_timeseries.mat'), ...
    'reflow_setpoint_ts', ...
    'conveyor_speed_ts', ...
    'motor_current_ts', ...
    'vibration_ts', ...
    'operating_hours_ts');

%% Create Simulink model

new_system(model);
open_system(model);

set_param(model, 'StopTime', num2str(t(end)));
set_param(model, 'Solver', 'ode45');

x0 = 40; 
y0 = 70; 
dx = 165; 
dy = 90;

sensorY = y0 + 2*dy;

%% Main temperature control chain

add_block('simulink/Sources/From Workspace', [model '/Reflow_Temperature_Setpoint'], ...
    'VariableName', 'reflow_setpoint_ts', ...
    'Position', [x0 y0 x0+130 y0+45]);

add_block('simulink/Math Operations/Sum', [model '/Temperature_Error_Sum'], ...
    'Inputs', '+-', ...
    'Position', [x0+dx y0+5 x0+dx+45 y0+45]);

add_block('simulink/Continuous/PID Controller', [model '/PID_Controller'], ...
    'Position', [x0+2*dx y0 x0+2*dx+115 y0+50]);

add_block('simulink/Discontinuities/Saturation', [model '/Heater_Power_Limit'], ...
    'UpperLimit', '100', ...
    'LowerLimit', '0', ...
    'Position', [x0+3*dx y0 x0+3*dx+110 y0+50]);

% First-order thermal model.
% This block outputs temperature rise above ambient temperature.
add_block('simulink/Continuous/Transfer Fcn', [model '/Reflow_Oven_Thermal_Model'], ...
    'Numerator', ['[' num2str(thermalGain) ']'], ...
    'Denominator', ['[' num2str(thermalTau) ' 1]'], ...
    'Position', [x0+4*dx y0 x0+4*dx+145 y0+50]);

% Ambient temperature block
add_block('simulink/Sources/Constant', [model '/Ambient_Temperature'], ...
    'Value', num2str(Tamb), ...
    'Position', [x0+4*dx y0+80 x0+4*dx+110 y0+110]);

% Sensor noise block
add_block('simulink/Sources/Random Number', [model '/Temperature_Noise'], ...
    'Mean', '0', ...
    'Variance', '0.3', ...
    'Seed', '123', ...
    'SampleTime', '1', ...
    'Position', [x0+4*dx y0+135 x0+4*dx+110 y0+175]);

% Actual temperature = thermal response + ambient temperature + noise
add_block('simulink/Math Operations/Sum', [model '/Actual_Temperature_With_Noise'], ...
    'Inputs', '+++', ...
    'Position', [x0+5*dx y0+5 x0+5*dx+45 y0+45]);

add_block('simulink/Signal Routing/Mux', [model '/Temperature_Mux'], ...
    'Inputs', '2', ...
    'Position', [x0+6*dx-55 y0-5 x0+6*dx-25 y0+60]);

add_block('simulink/Sinks/Scope', [model '/Temperature_Scope'], ...
    'Position', [x0+6*dx+30 y0-5 x0+6*dx+115 y0+65]);

%% Extra visualisation scopes
% These scopes make the Simulink model easier to explain during presentation.
% They show process signals and SMT sensor signals directly inside Simulink.

% Process signals: temperature error and heater power
add_block('simulink/Signal Routing/Mux', [model '/Process_Mux'], ...
    'Inputs', '2', ...
    'Position', [x0+6*dx-55 y0+145 x0+6*dx-25 y0+205]);

add_block('simulink/Sinks/Scope', [model '/Process_Scope'], ...
    'Position', [x0+6*dx+30 y0+140 x0+6*dx+130 y0+215]);

% SMT sensor signals: conveyor speed, motor current, vibration
add_block('simulink/Signal Routing/Mux', [model '/SMT_Sensor_Mux'], ...
    'Inputs', '3', ...
    'Position', [x0+2*dx+90 sensorY+25 x0+2*dx+120 sensorY+105]);

add_block('simulink/Sinks/Scope', [model '/SMT_Sensor_Scope'], ...
    'Position', [x0+3*dx sensorY+20 x0+3*dx+120 sensorY+115]);

% Operating hours is shown separately because its scale is much larger
add_block('simulink/Sinks/Scope', [model '/Operating_Hours_Scope'], ...
    'Position', [x0+3*dx sensorY+3*dy x0+3*dx+120 sensorY+3*dy+60]);
%% Workspace output blocks

add_block('simulink/Sinks/To Workspace', [model '/setpoint_temperature_out'], ...
    'VariableName', 'setpoint_temperature', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+dx y0-75 x0+dx+125 y0-45]);

add_block('simulink/Sinks/To Workspace', [model '/temperature_error_out'], ...
    'VariableName', 'temperature_error', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+2*dx y0+80 x0+2*dx+125 y0+110]);

add_block('simulink/Sinks/To Workspace', [model '/heater_power_out'], ...
    'VariableName', 'heater_power', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+4*dx-20 y0-75 x0+4*dx+110 y0-45]);

add_block('simulink/Sinks/To Workspace', [model '/actual_temperature_out'], ...
    'VariableName', 'actual_temperature', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+6*dx+30 y0+90 x0+6*dx+160 y0+120]);

%% Additional SMT sensor signals

add_block('simulink/Sources/From Workspace', [model '/Conveyor_Speed_Signal'], ...
    'VariableName', 'conveyor_speed_ts', ...
    'Position', [x0 sensorY x0+130 sensorY+45]);

add_block('simulink/Sources/From Workspace', [model '/Motor_Current_Signal'], ...
    'VariableName', 'motor_current_ts', ...
    'Position', [x0 sensorY+dy x0+130 sensorY+dy+45]);

add_block('simulink/Sources/From Workspace', [model '/Vibration_Signal'], ...
    'VariableName', 'vibration_ts', ...
    'Position', [x0 sensorY+2*dy x0+130 sensorY+2*dy+45]);

add_block('simulink/Sources/From Workspace', [model '/Operating_Hours_Signal'], ...
    'VariableName', 'operating_hours_ts', ...
    'Position', [x0 sensorY+3*dy x0+130 sensorY+3*dy+45]);

add_block('simulink/Sinks/To Workspace', [model '/conveyor_speed_out'], ...
    'VariableName', 'conveyor_speed', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+dx sensorY x0+dx+130 sensorY+45]);

add_block('simulink/Sinks/To Workspace', [model '/motor_current_out'], ...
    'VariableName', 'motor_current', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+dx sensorY+dy x0+dx+130 sensorY+dy+45]);

add_block('simulink/Sinks/To Workspace', [model '/vibration_out'], ...
    'VariableName', 'vibration', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+dx sensorY+2*dy x0+dx+130 sensorY+2*dy+45]);

add_block('simulink/Sinks/To Workspace', [model '/operating_hours_out'], ...
    'VariableName', 'operating_hours', ...
    'SaveFormat', 'Structure With Time', ...
    'Position', [x0+dx sensorY+3*dy x0+dx+130 sensorY+3*dy+45]);

%% Connect main control chain

add_line(model, 'Reflow_Temperature_Setpoint/1', 'Temperature_Error_Sum/1', 'autorouting', 'on');
add_line(model, 'Temperature_Error_Sum/1', 'PID_Controller/1', 'autorouting', 'on');
add_line(model, 'PID_Controller/1', 'Heater_Power_Limit/1', 'autorouting', 'on');
add_line(model, 'Heater_Power_Limit/1', 'Reflow_Oven_Thermal_Model/1', 'autorouting', 'on');

add_line(model, 'Reflow_Oven_Thermal_Model/1', 'Actual_Temperature_With_Noise/1', 'autorouting', 'on');
add_line(model, 'Ambient_Temperature/1', 'Actual_Temperature_With_Noise/2', 'autorouting', 'on');
add_line(model, 'Temperature_Noise/1', 'Actual_Temperature_With_Noise/3', 'autorouting', 'on');

% Feedback actual temperature to calculate error
add_line(model, 'Actual_Temperature_With_Noise/1', 'Temperature_Error_Sum/2', 'autorouting', 'on');

% Scope: target vs actual
add_line(model, 'Reflow_Temperature_Setpoint/1', 'Temperature_Mux/1', 'autorouting', 'on');
add_line(model, 'Actual_Temperature_With_Noise/1', 'Temperature_Mux/2', 'autorouting', 'on');
add_line(model, 'Temperature_Mux/1', 'Temperature_Scope/1', 'autorouting', 'on');

% Workspace outputs
add_line(model, 'Reflow_Temperature_Setpoint/1', 'setpoint_temperature_out/1', 'autorouting', 'on');
add_line(model, 'Temperature_Error_Sum/1', 'temperature_error_out/1', 'autorouting', 'on');
add_line(model, 'Heater_Power_Limit/1', 'heater_power_out/1', 'autorouting', 'on');
add_line(model, 'Actual_Temperature_With_Noise/1', 'actual_temperature_out/1', 'autorouting', 'on');

%% Connect additional sensors to workspace outputs

add_line(model, 'Conveyor_Speed_Signal/1', 'conveyor_speed_out/1', 'autorouting', 'on');
add_line(model, 'Motor_Current_Signal/1', 'motor_current_out/1', 'autorouting', 'on');
add_line(model, 'Vibration_Signal/1', 'vibration_out/1', 'autorouting', 'on');
add_line(model, 'Operating_Hours_Signal/1', 'operating_hours_out/1', 'autorouting', 'on');

%% Connect signals to visualisation scopes
% Process scope: temperature error and heater power
add_line(model, 'Temperature_Error_Sum/1', 'Process_Mux/1', 'autorouting', 'on');
add_line(model, 'Heater_Power_Limit/1', 'Process_Mux/2', 'autorouting', 'on');
add_line(model, 'Process_Mux/1', 'Process_Scope/1', 'autorouting', 'on');

% SMT sensor scope: conveyor speed, motor current, vibration
add_line(model, 'Conveyor_Speed_Signal/1', 'SMT_Sensor_Mux/1', 'autorouting', 'on');
add_line(model, 'Motor_Current_Signal/1', 'SMT_Sensor_Mux/2', 'autorouting', 'on');
add_line(model, 'Vibration_Signal/1', 'SMT_Sensor_Mux/3', 'autorouting', 'on');
add_line(model, 'SMT_Sensor_Mux/1', 'SMT_Sensor_Scope/1', 'autorouting', 'on');

% Operating hours scope
add_line(model, 'Operating_Hours_Signal/1', 'Operating_Hours_Scope/1', 'autorouting', 'on');

%% Add annotation

ann = Simulink.Annotation(model, ...
    ['Smartphone PCB Assembly - Reflow Oven Demo', newline, ...
     'Main loop: setpoint -> PID -> heater limit -> thermal response + ambient temperature -> feedback.', newline, ...
     'Extra SMT sensor signals are exported for AI quality risk and maintenance risk prediction.', newline, ...
     'This can act as a supervisory monitoring layer for an automated / robotic SMT line.']);

try
    ann.Position = [520 420 800 90];
    ann.FontSize = 10;
catch
end

%% Save model

save_system(model, modelFile);

disp(['Created fixed Simulink model: ' modelFile]);
disp(['Simulation stop time: ' num2str(t(end)) ' seconds']);
disp('Next run: generate01_sensor_data_from_simulink_FIXED.m');