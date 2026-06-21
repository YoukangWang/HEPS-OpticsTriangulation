function [wCent,area,eDia,xy] = detectLaserSpotRobust(roiImage)
    % detectLaserSpotRobust: 高级激光检测，包含背景抑制与动态ROI生成
    % 输入:
    %   roiImage - 单通道灰度图

    % Median filter to filter out the salt and pepper noise.
    smoothedImg  = medfilt2(roiImage,[5,5]);
    % Smoothed image with Gaussian filter
    sigma = 5;
    smoothedImg  = imgaussfilt(smoothedImg,sigma);


    % % ==========================================
    % % 1. 背景抑制与二值化
    % % ==========================================
    % % 【推荐】方案 A: Top-Hat 滤波 (专治不均匀背景光)
    % % 半径设为 30，意味着它会消除所有宽度大于 60 像素的平缓背景光，只保留锐利的光斑
    % se = strel('disk', 100); 
    % I_bg_removed = imtophat(smoothedImg, se); 

    % 在干净的去背景图上执行二值化
    bw = imbinarize(rescale(smoothedImg), 'adaptive');


    % 形态学去噪 (去除细小杂讯)
    bw = bwareaopen(bw, 40); 

    % ==========================================
    % 2. 提取参数
    % ==========================================
    % 注意：加权质心必须依据原图 I 计算，而不是去背景后的图，以保证能量分布最原始
    tabBlob = regionprops('table',bw, roiImage, 'Area', 'WeightedCentroid', 'MaxIntensity','Circularity','EquivDiameter');
    tabBlob = sortrows(tabBlob,{'MaxIntensity','Area','Circularity'},{'descend','descend','descend'});

    if isempty(tabBlob) || tabBlob.Circularity(1)<0.4
        wCent = [];
        area=[];
        eDia = [];
        xy = [];
        return;
    end

    % 提取最大连通域参数
    wCent = tabBlob.WeightedCentroid(1,:);
    area = tabBlob.Area(1);
    eDia = tabBlob.EquivDiameter(1);

    % ==========================================
    % 3. 生成安全的动态 ROI
    % ==========================================
    
    % 计算原始矩形的对角坐标 (四舍五入为整数索引)
    w = 6*eDia;
    h = 8*eDia;
    x1 = round(wCent(1) - w/2);
    y1 = round(wCent(2) - h/2);
    x2 = round(x1 + w - 1);
    y2 = round(y1 + h - 1);


    xy = [x1, y1, x2, y2];
end