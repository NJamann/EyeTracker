
%% paths & files
clear all;
strVidFile = 'X:\JorritMontijn\DataNeuropixels\EyeTrackingRaw2019-11-21_MP2_R01.mp4'; %target file
strMiniVidPath = 'D:\Data\Processed\Neuropixels\minivid\'; %will save small video of pupil ROI here
strTempDirDefault = 'E:\_TempData'; % path to temporary binary file (same size as data, should be on fast SSD)

%% set the parameters here
dblThreshSync = 18;%sync threshold luminance
vecRectROI = [179 50 131 92];%Pupil ROI: [x-from-left y-from-top x-width y-height]
vecRectSync = [1 430 147 54];%Sync ROI: [x-from-left y-from-top x-width y-height]

%thresholds
dblGaussWidth = 0; %blur image with gaussian filter: width
sglReflT = 200;%remove all pixels above this value as reflections
sglPupilT = 10;%all pixels below this value could be the pupil

%% prepare
%check temp path free space
objFile      = java.io.File(strTempDirDefault(1:3));
dblFreeBytes   = objFile.getFreeSpace;
if dblFreeBytes > (10*(1024.^3)) %10 gb min
	strTempDir = strTempDirDefault;
	fprintf('Using temp dir "%s" (%.1fGB free)\n',strTempDir,dblFreeBytes/(1024.^3));
else
	strTempDir(1) = 'D';
	fprintf('Not enough space on SSD (%.1fGB free). Using temp dir "%s"\n',dblFreeBytes/(1024.^3),strTempDir);
end

%% fixed
%find video file
sVidFiles = dir(strVidFile);
if numel(sVidFiles) == 1
	strVideoFile = sVidFiles.name;
	strPath = sVidFiles.folder;
else
	error([mfilename ':AmbiguousInput'],'Multiple video files found, please narrow search parameters');
end
if ~strcmp(strPath(end),filesep),strPath(end+1) = filesep;end
if ~strcmp(strTempDir(end),filesep),strTempDir(end+1) = filesep;end

%% copy file to local temp directory
fprintf('Copying "%s" to local path "%s" [%s]\n',strVideoFile,strTempDir,getTime);
[status1,msg1,msgID1] = copyfile([strPath strVideoFile],[strTempDir strVideoFile]);

%% make figure
fprintf('Processing "%s" [%s]\n',strVideoFile,getTime);
hFig = figure;
ptrAxesMainVideo = subplot(3,3,[1 2 4 5]);
ptrAxesSubVid1 = subplot(3,3,3);
ptrAxesSubVid2 = subplot(3,3,6);
ptrAxesSubVid3 = subplot(3,3,7);
ptrAxesSubVid4 = subplot(3,3,8);
ptrAxesSubVid5 = subplot(3,3,9);

%% load data
objVid = VideoReader([strTempDir strVideoFile]);

%% get data
intSizeX = objVid.Width;
intSizeY = objVid.Height;
dblTotDur = objVid.Duration;
dblFrameRate = objVid.FrameRate;
intTotFrames = objVid.NumberOfFrames;

%% define variables from parameters
%build structuring elements
intRadStrEl = 2;
objSE = strel('disk',intRadStrEl,4);
vecKeepY = vecRectROI(2):(vecRectROI(2)+vecRectROI(4));
vecKeepX = vecRectROI(1):(vecRectROI(1)+vecRectROI(3));

%rebuild ROI
vecPlotRectX = [vecRectROI(1) vecRectROI(1) vecRectROI(1)+vecRectROI(3) vecRectROI(1)+vecRectROI(3) vecRectROI(1)];
vecPlotRectY = [vecRectROI(2) vecRectROI(2)+vecRectROI(4) vecRectROI(2)+vecRectROI(4) vecRectROI(2) vecRectROI(2)];

%Sync ROI: [x-from-left y-from-top x-width y-height]
vecSyncY = vecRectSync(2):(vecRectSync(2)+vecRectSync(4));
vecSyncX = vecRectSync(1):(vecRectSync(1)+vecRectSync(3));
%rebuild ROI
vecPlotSyncX = [vecRectSync(1) vecRectSync(1) vecRectSync(1)+vecRectSync(3) vecRectSync(1)+vecRectSync(3) vecRectSync(1)];
vecPlotSyncY = [vecRectSync(2) vecRectSync(2)+vecRectSync(4) vecRectSync(2)+vecRectSync(4) vecRectSync(2) vecRectSync(2)];

%blur width
if dblGaussWidth == 0
	gMatFilt = gpuArray(single(1));
else
	intGaussSize = ceil(dblGaussWidth*2);
	vecFilt = normpdf(-intGaussSize:intGaussSize,0,dblGaussWidth);
	matFilt = vecFilt' * vecFilt;
	matFilt = matFilt / sum(matFilt(:));
	gMatFilt = gpuArray(single(matFilt));
end
vecPupilT = (-3:1:1) + sglPupilT;
vecBlinkWindow = round([-0.125 0.125]*dblFrameRate);

%% pre-allocate
%save output
vecPupilTime = nan(1,intTotFrames);
vecPupilVidFrame = nan(1,intTotFrames);
vecPupilSyncLum = nan(1,intTotFrames);
vecPupilSyncPulse = nan(1,intTotFrames);
vecPupilCenterX = nan(1,intTotFrames);
vecPupilCenterY = nan(1,intTotFrames);
vecPupilRadius = nan(1,intTotFrames);
vecPupilEdgeHardness = nan(1,intTotFrames);
vecPupilMeanPupilLum = nan(1,intTotFrames);
vecPupilSdPupilLum = nan(1,intTotFrames);
vecPupilAbsVidLum = nan(1,intTotFrames);
vecPupilRelVidLum = nan(1,intTotFrames);
vecPupilApproxConfidence = nan(1,intTotFrames);
vecPupilApproxRoundness = nan(1,intTotFrames);
vecPupilApproxRadius = nan(1,intTotFrames);

%% define color map
matC = ...
	[0 0 0;... %0, nothing
	1 0 0;... %1, reflection
	0 1 0;... %2, potential pupil regions
	1 1 0;... %3, reflection & potential pupil
	0 1 1;... %4, pupil
	1 0 1;... %5, reflection & pupil
	1 1 1;... %6, potential pupil & pupil
	0 0 1;... %7, potential pupil & pupil & reflection
	];

%% perform pupil detection
hTicCompStart = tic;
dblLastShow = -inf;
dblShowInterval = 0.5;
vecPrevLoc = [0;0];
strMiniOut = strrep(strVideoFile,'Raw','MiniVid');
objVid = VideoReader([strTempDir strVideoFile]); %recreate becase of NumberOfFrames... don't ask why...
objMiniVid = VideoWriter([strTempDir strMiniOut],'MPEG-4');
objMiniVid.FrameRate = objVid.FrameRate;
open(objMiniVid);
boolInitDone = false;
intFrame = 0;
intSyncPulse = 0;
boolSyncHigh = false;
while hasFrame(objVid)
	%% read frame and add to buffer
	intFrame = intFrame + 1;
	try
		matVidRaw = readFrame(objVid);
		matVidBuffer = matVidRaw;
	catch
		pause(0.5);
		warning([mfilename ':ReadError'],sprintf('Frame %d/%d (t=%.3s) could not be read',intFrame,intTotFrames,dblCurTime));
	end
	dblCurTime = objVid.CurrentTime;
	
	%select ROI
	dblAbsVidLum = mean(flat(matVidBuffer(:,:,1,:)));
	matVid = imnorm(mean(single(matVidBuffer(:,:,1,:)),4));
	gMatVid = gpuArray(matVid(vecKeepY,vecKeepX));
	
	%write mini vid
	writeVideo(objMiniVid,matVid(vecKeepY,vecKeepX));
	
	%find pupil
	[sPupil,imPupil,imReflection,imBW] = getPupil(gMatVid,gMatFilt,sglReflT,sglPupilT,objSE,vecPrevLoc,vecPupilT);
	%make plotting map
	matPlot = imReflection + imBW*2 + imPupil * 4;
	
	%get synchronization pulse window luminance
	dblSyncLum = mean(flat(matVidBuffer(vecSyncY,vecSyncX,1,end)));
	boolLastSyncHigh = boolSyncHigh;
	boolSyncHigh = dblSyncLum > dblThreshSync;
	if boolSyncHigh && (boolLastSyncHigh ~= boolSyncHigh)
		intSyncPulse = intSyncPulse + 1;
	end
	
	%extract parameters
	vecCentroid = sPupil.vecCentroid; %center in pixel coordinates
	dblRadius = sPupil.dblRadius; %radius in pixels
	dblEdgeHardness = sPupil.dblEdgeHardness; %0 if uniform (no edge), 1 if mask drops from 1 to 0 at exactly the fitted boundary
	dblMeanPupilLum = sPupil.dblMeanPupilLum; %average pupil area intensity
	dblSdPupilLum = sPupil.dblSdPupilLum; %sd of pupil area intensity
	dblApproxConfidence = sPupil.dblApproxConfidence; %confidence of approximated pupil parameters
	dblApproxRoundness = sPupil.dblApproxRoundness; %approximated pupil roundness
	vecApproxCentroid = sPupil.vecApproxCentroid; %approximated pupil centroid
	dblApproxRadius = sPupil.dblApproxRadius; %approximated pupil radius
	
	vecPrevLoc = vecCentroid;
	
	if (dblCurTime - dblLastShow > dblShowInterval) || dblRadius == 0
		%update counter
		dblLastShow = dblCurTime;
		%% video
		%show video with overlays
		imagesc(ptrAxesMainVideo,matVid);
		colormap(ptrAxesMainVideo,'grey');
		hold(ptrAxesMainVideo,'on');
		plot(ptrAxesMainVideo,vecPlotSyncX,vecPlotSyncY,'c--');
		plot(ptrAxesMainVideo,vecPlotRectX,vecPlotRectY,'b--');
		dblX = vecCentroid(1) + vecPlotRectX(1);
		dblY = vecCentroid(2) + vecPlotRectY(1);
		ellipse(ptrAxesMainVideo,dblX,dblY,dblRadius,dblRadius,'Color','r','LineStyle','-','LineWidth',1);
		hold(ptrAxesMainVideo,'off');
		title(ptrAxesMainVideo,sprintf('Frame %d/%d (FR: %.3fs), T=%.3fs/%.3fs, Computation time: %.0fs',intFrame,intTotFrames,dblFrameRate,dblCurTime,dblTotDur,toc(hTicCompStart)));
		
		%regions
		imagesc(ptrAxesSubVid1,matPlot);
		set(ptrAxesSubVid1,'CLim',[0 7]);
		colormap(ptrAxesSubVid1,matC);
		title(ptrAxesSubVid1,strVideoFile,'Interpreter','none');
		
		%blow-up
		imagesc(ptrAxesSubVid2,gMatVid);
		colormap(ptrAxesSubVid2,'grey');
		hold(ptrAxesSubVid2,'on');
		ellipse(ptrAxesSubVid2,vecCentroid(1),vecCentroid(2),dblRadius,dblRadius,'Color','r','LineStyle','-','LineWidth',1);
		axis(ptrAxesSubVid2,'off');
		
		%% curves
		%check which frames to remove due to blinking
		vecBlinkFrames = unique((vecBlinkWindow(1):vecBlinkWindow(end)) + find(abs(nanzscore(vecPupilEdgeHardness)) > 6)');
		vecBlinkFrames(vecBlinkFrames > intFrame) = [];
		vecPlotT = vecPupilTime(1:intFrame);
		
		%get data
		vecPlotPupilX = nanzscore(vecPupilCenterX(1:intFrame));
		vecPlotPupilY = nanzscore(vecPupilCenterY(1:intFrame));
		vecPlotPupilR = nanzscore(vecPupilRadius(1:intFrame));
		
		vecPlotMeanPupLum = nanzscore(vecPupilMeanPupilLum(1:intFrame));
		vecPlotApproxConf = nanzscore(vecPupilApproxConfidence(1:intFrame));
		vecPlotSyncLum = nanzscore(vecPupilSyncLum(1:intFrame));
		
		%remove blinks
		vecPlotPupilX(vecBlinkFrames) = nan;
		vecPlotPupilY(vecBlinkFrames) = nan;
		vecPlotPupilR(vecBlinkFrames) = nan;
		
		vecPlotMeanPupLum(vecBlinkFrames) = nan;
		vecPlotApproxConf(vecBlinkFrames) = nan;
		
		%binkiness
		vecBlinkiness = -nanzscore(vecPupilEdgeHardness(1:intFrame));
		plot(ptrAxesSubVid3,vecPlotT,vecBlinkiness,'r');
		hold(ptrAxesSubVid3,'on');
		plot(ptrAxesSubVid3,vecPlotT,vecPlotSyncLum,'b');
		hold(ptrAxesSubVid3,'off');
		title(ptrAxesSubVid3,'R=Blink likelihood, B=Sync Lum');
		xlabel(ptrAxesSubVid3,'Time (s)');
		ylabel(ptrAxesSubVid3,'Value (z-score)');
		fixfig(ptrAxesSubVid3,0);
		
		%lum
		plot(ptrAxesSubVid4,vecPlotT,vecPlotApproxConf,'b');
		hold(ptrAxesSubVid4,'on');
		plot(ptrAxesSubVid4,vecPlotT,vecPlotMeanPupLum,'r');
		hold(ptrAxesSubVid4,'off');
		title(ptrAxesSubVid4,'R=Pupil Lum, B = Conf');
		xlabel(ptrAxesSubVid4,'Time (s)');
		ylabel(ptrAxesSubVid4,'Value (z-score)');
		fixfig(ptrAxesSubVid4,0);
		
		%x,y,r
		plot(ptrAxesSubVid5,vecPlotT,vecPlotPupilX,'r');
		hold(ptrAxesSubVid5,'on');
		plot(ptrAxesSubVid5,vecPlotT,vecPlotPupilY,'g');
		plot(ptrAxesSubVid5,vecPlotT,vecPlotPupilR,'b');
		hold(ptrAxesSubVid5,'off');
		title(ptrAxesSubVid5,'R=x, G=y, B=Radius');
		xlabel(ptrAxesSubVid5,'Time (s)');
		ylabel(ptrAxesSubVid5,'Value (z-score)');
		fixfig(ptrAxesSubVid5,0);
		drawnow;
		
		
		%check if we should pause
		%if dblCurTime > 4 && dblMajAx == 0
		%	title(ptrAxesSubVid2,'PAUSED')
		%	drawnow;
		%	pause;
		%end
	end
	
	%save output
	vecPupilTime(intFrame) = dblCurTime;
	vecPupilVidFrame(intFrame) = intFrame;
	vecPupilSyncLum(intFrame) = dblSyncLum;
	vecPupilSyncPulse(intFrame) = intSyncPulse;
	vecPupilCenterX(intFrame) = vecCentroid(1);
	vecPupilCenterY(intFrame) = vecCentroid(2);
	vecPupilRadius(intFrame) = dblRadius;
	vecPupilEdgeHardness(intFrame) = dblEdgeHardness;
	vecPupilMeanPupilLum(intFrame) = dblMeanPupilLum;
	vecPupilSdPupilLum(intFrame) = dblSdPupilLum;
	vecPupilAbsVidLum(intFrame) = dblAbsVidLum;
	vecPupilApproxConfidence(intFrame) = dblApproxConfidence;
	vecPupilApproxRoundness(intFrame) = dblApproxRoundness;
	vecPupilApproxRadius(intFrame) = dblApproxRadius;
	
end
close(objMiniVid);

%% interpolate detection failures
%initial roundness check
indWrongA = sqrt(zscore(vecPupilCenterX).^2 + zscore(vecPupilCenterY).^2) > 4;
indWrong1 = conv(indWrongA,ones(1,5),'same')>0;
vecAllPoints1 = 1:numel(indWrong1);
vecGoodPoints1 = find(~indWrong1);
vecTempX = interp1(vecGoodPoints1,vecPupilCenterX(~indWrong1),vecAllPoints1);
vecTempY = interp1(vecGoodPoints1,vecPupilCenterY(~indWrong1),vecAllPoints1);
%remove position outliers
indWrongB = abs(nanzscore(vecTempX)) > 4 | abs(nanzscore(vecTempY)) > 4;
%define final removal vector
indWrong = conv(indWrongA | indWrongB,ones(1,5),'same')>0;
vecAllPoints = 1:numel(indWrong);
vecGoodPoints = find(~indWrong);

%fix
vecPupilFixedCenterX = interp1(vecGoodPoints,vecPupilCenterX(~indWrong),vecAllPoints,'linear','extrap');
vecPupilFixedCenterY = interp1(vecGoodPoints,vecPupilCenterY(~indWrong),vecAllPoints,'linear','extrap');
vecPupilFixedRadius = interp1(vecGoodPoints,vecPupilRadius(~indWrong),vecAllPoints,'linear','extrap');

%% gather data
%check which frames to remove
intLastFrame = find(~(isnan(vecPupilApproxConfidence) | vecPupilApproxConfidence == 0),1,'last');
vecPupilTime = vecPupilTime(1:intLastFrame);
vecPupilVidFrame = vecPupilVidFrame(1:intLastFrame);
vecPupilSyncLum = vecPupilSyncLum(1:intLastFrame);
vecPupilSyncPulse = vecPupilSyncPulse(1:intLastFrame);
vecPupilCenterX = vecPupilCenterX(1:intLastFrame);
vecPupilCenterY = vecPupilCenterY(1:intLastFrame);
vecPupilRadius = vecPupilRadius(1:intLastFrame);
vecPupilEdgeHardness = vecPupilEdgeHardness(1:intLastFrame);
vecPupilMeanPupilLum = vecPupilMeanPupilLum(1:intLastFrame);
vecPupilAbsVidLum = vecPupilAbsVidLum(1:intLastFrame);
vecPupilSdPupilLum = vecPupilSdPupilLum(1:intLastFrame);
vecPupilApproxConfidence = vecPupilApproxConfidence(1:intLastFrame);
vecPupilApproxRoundness = vecPupilApproxRoundness(1:intLastFrame);
vecPupilApproxRadius = vecPupilApproxRadius(1:intLastFrame);

vecPupilFixedCenterX = vecPupilFixedCenterX(1:intLastFrame);
vecPupilFixedCenterY = vecPupilFixedCenterY(1:intLastFrame);
vecPupilFixedRadius = vecPupilFixedRadius(1:intLastFrame);

%put in struct
sPupil = struct;
sPupil.vecPupilTime = vecPupilTime;
sPupil.vecPupilVidFrame = vecPupilVidFrame;
sPupil.vecPupilSyncLum = vecPupilSyncLum;
sPupil.vecPupilSyncPulse = vecPupilSyncPulse;

%raw
sPupil.vecPupilCenterX = vecPupilCenterX;
sPupil.vecPupilCenterY = vecPupilCenterY;
sPupil.vecPupilRadius = vecPupilRadius;
sPupil.vecPupilEdgeHardness = vecPupilEdgeHardness;
sPupil.vecPupilMeanPupilLum = vecPupilMeanPupilLum;
sPupil.vecPupilAbsVidLum = vecPupilAbsVidLum;

sPupil.vecPupilSdPupilLum = vecPupilSdPupilLum;
sPupil.vecPupilApproxConfidence = vecPupilApproxConfidence;
sPupil.vecPupilApproxRoundness = vecPupilApproxRoundness;
sPupil.vecPupilApproxRadius = vecPupilApproxRadius;

%fixed
sPupil.vecPupilFixedCenterX = vecPupilFixedCenterX;
sPupil.vecPupilFixedCenterY = vecPupilFixedCenterY;
sPupil.vecPupilFixedRadius = vecPupilFixedRadius;

%create filename
strVideoOut = strrep(strVideoFile,'Raw','Processed');
strVideoOut(find(strVideoOut=='.',1,'last'):end) = [];
strVideoOut = strcat(strVideoOut,'.mat');

%extra info
sPupil.strVideoFile = strVideoFile;
sPupil.strMiniVidPath = strMiniVidPath;
sPupil.strMiniVidFile = strVideoOut;

%% save file
%save
save([strPath strVideoOut],'sPupil');
fprintf('Saved data to %s (source: %s, path: %s) [%s]\n',strVideoOut,strVideoFile,strPath,getTime);

%copy mini vid
copyfile([strTempDir strMiniOut],[strPath strMiniOut]);
fprintf('Saved minivid to %s (source: %s, path: %s) [%s]\n',strMiniOut,strTempDir,strMiniOut,getTime);

%% plot
figure
subplot(2,1,1)
plot(sPupil.vecPupilTime,sPupil.vecPupilCenterX);
hold on
plot(sPupil.vecPupilTime,sPupil.vecPupilFixedCenterX);
hold off
title(sprintf('Pupil pos x, %s',strVideoFile),'Interpreter','none');
xlabel('Time (s)');
ylabel('Pupil x-position');
fixfig

subplot(2,1,2)
plot(sPupil.vecPupilTime,sPupil.vecPupilCenterY);
hold on
plot(sPupil.vecPupilTime,sPupil.vecPupilFixedCenterY);
hold off
title(sprintf('Pupil pos y, %s',strVideoFile),'Interpreter','none');
xlabel('Time (s)');
ylabel('Pupil y-position');
fixfig