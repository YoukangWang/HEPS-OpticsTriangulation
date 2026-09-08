function [wCent, area, eDia, xy] = detectLaserSpotRobust(roiImage)
% detectLaserSpotRobust: 稳健激光光斑检测，含背景抑制与亚像素质心
% 输入: roiImage - 单通道灰度图 (double, ROI局部坐标)
% 输出: wCent [x,y] 亚像素质心, area 面积, eDia 等效直径, xy [x1 y1 x2 y2] 新动态ROI

    [H, W] = size(roiImage);

    % ---- 1. 预处理 ----
    % 轻量中值滤波去椒盐噪声
    filtered = medfilt2(roiImage, [3, 3]);

    % Top-Hat 滤波抑制不均匀背景（保留比结构元半径小的亮特征）
    % 半径35约为典型光斑直径的1.5~2倍，可根据实际光斑大小调整
    se = strel('disk', 35);
    bgRemoved = imtophat(filtered, se);

    % 轻量高斯平滑（sigma=2，比原来的5更快且不模糊光斑）
    smoothed = imgaussfilt(bgRemoved, 2);

    % ---- 2. 二值化（Otsu全局阈值，比adaptive更快更稳定）----
    normImg = rescale(smoothed);
    T = max(graythresh(normImg), 0.25);  % 保底阈值防低对比度误检
    bw = normImg >= T;
    bw = bwareaopen(bw, 20);

    % ---- 3. 候选光斑筛选 ----
    tabBlob = regionprops('table', bw, roiImage, ...
        'Area', 'WeightedCentroid', 'MaxIntensity', 'Circularity', 'EquivDiameter');

    if isempty(tabBlob)
        [wCent, area, eDia, xy] = deal([], [], [], []);
        return;
    end

    % 圆度过滤（排除线状/块状噪声）
    tabBlob = tabBlob(tabBlob.Circularity >= 0.35, :);
    if isempty(tabBlob)
        [wCent, area, eDia, xy] = deal([], [], [], []);
        return;
    end

    % 综合评分：亮度×圆度，优先选真实光斑而非大面积低圆度噪声
    [~, idx] = max(tabBlob.MaxIntensity .* tabBlob.Circularity);

    area = tabBlob.Area(idx);
    eDia = tabBlob.EquivDiameter(idx);
    coarseCent = tabBlob.WeightedCentroid(idx, :);

    % ---- 4. 亚像素质心精化（在背景抑制图上加权矩，消除背景偏置）----
    r  = max(ceil(eDia * 1.5), 8);
    cx = round(coarseCent(1));
    cy = round(coarseCent(2));
    px1 = max(1, cx - r);  px2 = min(W, cx + r);
    py1 = max(1, cy - r);  py2 = min(H, cy + r);

    patch = bgRemoved(py1:py2, px1:px2);
    [gx, gy] = meshgrid(px1:px2, py1:py2);
    ws = sum(patch(:));
    if ws > 0
        wCent = [sum(gx(:) .* patch(:)) / ws, ...
                 sum(gy(:) .* patch(:)) / ws];
    else
        wCent = coarseCent;
    end

    % ---- 5. 动态 ROI（跟踪窗口，供下一帧使用）----
    margin = 6 * eDia;
    x1 = round(wCent(1) - margin / 2);
    y1 = round(wCent(2) - margin / 2);
    x2 = round(x1 + margin - 1);
    y2 = round(y1 + margin - 1);
    xy = [x1, y1, x2, y2];
end