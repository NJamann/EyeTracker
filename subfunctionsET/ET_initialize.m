function [sEyeFig,sET] = ET_initialize(sEyeFig,sET)
	%OT_initialize initializes all fields when data paths are set
	
	%% initialize camera
	%set parameters
	intTriggerType = 1;
	
	%get devices
	sDevices = imaqhwinfo;
	
	%establish connection
	sCams = imaqhwinfo(sDevices.InstalledAdaptors{1},1);
	objCam = eval(sCams.VideoDeviceConstructor);%imaq.VideoDevice('gentl', 1)
	objVid = eval(sCams.VideoInputConstructor);%videoinput('gentl', 1)
	
	%get cam properties
	dblRealFrameRate = objCam.DeviceProperties.ResultingFrameRate;
	
	%set trigger mode
	if intTriggerType == 1
		%set acquisition to be triggered manually form matlab
		triggerconfig(objVid,'immediate');
	elseif intTriggerType == 2
		%set acquisition to be triggered externally as ttl pulse to camera
		triggerconfig(objVid,'hardware','risingEdge','TTL');
	else
		
	end
	
	%set callback functions
	objVid.StartFcn = [];
	objVid.StopFcn = [];
	
	%set frames per trigger
	objVid.FramesPerTrigger = inf;
	
	%set disk logging to videowriter
	objVid.LoggingMode = 'memory';
	
	%video size
	intMaxX = objCam.ROI(3); %video size x
	intMaxY = objCam.ROI(4); %video size y
	%assign to global
	sET.intMaxX = intMaxX;
	sET.intMaxY = intMaxY;
	sET.sDevices = sDevices;
	sET.objCam = objCam;
	sET.objVid = objVid;
	sET.dblRealFrameRate = dblRealFrameRate;
	
	%% update figure controls to match data
	%set cam data
	set(sEyeFig.ptrListSelectAdaptor,'String',sDevices.InstalledAdaptors);
	set(sEyeFig.ptrListSelectDevice,'String',sCams.DeviceName);
	set(sEyeFig.ptrTextCamFormat,'String',objCam.VideoFormat);
	set(sEyeFig.ptrTextCamVideoSize,'String',strcat(num2str(intMaxX),' x ',num2str(intMaxY),' (X by Y)'));
	set(sEyeFig.ptrTextCamFramerate,'String',sprintf('%.3f',dblRealFrameRate));
	
	%set pupil/sync ROI slider positions
	set(sEyeFig.ptrSliderPupilROIStartLocX,'Value',sET.vecRectROI(1)/intMaxX);
	set(sEyeFig.ptrSliderPupilROIStartLocY,'Value',sET.vecRectROI(2)/intMaxY);
	set(sEyeFig.ptrSliderPupilROIStopLocX,'Value',(sET.vecRectROI(3)+sET.vecRectROI(1))/intMaxX);
	set(sEyeFig.ptrSliderPupilROIStopLocY,'Value',(sET.vecRectROI(4)+sET.vecRectROI(2))/intMaxY);
	
	set(sEyeFig.ptrSliderSyncROIStartLocX,'Value',sET.vecRectSync(1)/intMaxX);
	set(sEyeFig.ptrSliderSyncROIStartLocY,'Value',sET.vecRectSync(2)/intMaxY);
	set(sEyeFig.ptrSliderSyncROIStopLocX,'Value',(sET.vecRectSync(3)+sET.vecRectROI(1))/intMaxX);
	set(sEyeFig.ptrSliderSyncROIStopLocY,'Value',(sET.vecRectSync(4)+sET.vecRectROI(2))/intMaxY);
	
	%set pupil detection settings
	set(sEyeFig.ptrEditTempAvg,'String',num2str(sET.intTempAvg));
	set(sEyeFig.ptrEditBlurWidth,'String',sprintf('%.1f',sET.dblGaussWidth));
	set(sEyeFig.ptrEditMinRadius,'String',sprintf('%.1f',sET.dblPupilMinRadius));
	set(sEyeFig.ptrEditReflectLum,'String',num2str(sET.dblThreshReflect));
	set(sEyeFig.ptrEditPupilLum,'String',num2str(sET.dblThreshPupil));
	
	%% finalize and set msg
	cellText = {'Eye Tracker initialized!'};
	OT_updateTextInformation(cellText);
end
