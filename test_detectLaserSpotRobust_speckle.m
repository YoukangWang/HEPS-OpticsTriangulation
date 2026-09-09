function test_detectLaserSpotRobust_speckle
% test_detectLaserSpotRobust_speckle 验证散斑场景下光斑检测不缩小ROI
%
% 构造粗糙表面激光光斑：一块大高斯亮斑（真实激光光斑）内部叠加
% 多个像素级高对比度散斑亮核。旧版评分(亮度×圆度)会选中某个
% 小散斑亮核，导致eDia很小、margin=6*eDia很小、ROI正反馈缩小。
% 修复版应选中整块大光斑，ROI边长≥60px下限。

    rng(42); % 可复现
    W = 400; H = 400;

    % 大激光光斑：高斯亮斑，直径~80px
    [X, Y] = meshgrid(1:W, 1:H);
    cx = 200; cy = 200; sigmaSpot = 18;
    spot = 0.9 * exp(-((X-cx).^2 + (Y-cy).^2) / (2*sigmaSpot^2));

    % 粗糙表面散斑：50个像素级高对比度亮核散布在光斑内外
    speckle = zeros(H, W);
    for k = 1:50
        sx = randi([150 250]); sy = randi([150 250]); % 集中在光斑区
        speckle(sy, sx) = 1.0; % 饱和亮点，亮度高于光斑主体
        if sx+1<=W, speckle(sy, sx+1) = 0.9; end
    end
    % 加少量光斑外散斑干扰
    for k = 1:10
        sx = randi([1 W]); sy = randi([1 H]);
        speckle(sy, sx) = 0.85;
    end

    img = max(spot, speckle);
    img = img + 0.02 * randn(H, W); % 微噪声
    img = max(img, 0);

    roiImage = double(img);

    % 新签名: 第二参数测试默认值60（不传）
    [wCent, area, eDia, xy] = detectLaserSpotRobust(roiImage);

    fprintf('wCent = [%.2f, %.2f] (真值 [200,200])\n', wCent(1), wCent(2));
    fprintf('area = %.0f (大光斑预期 >1000)\n', area);
    fprintf('eDia  = %.2f (大光斑预期 >30)\n', eDia);
    fprintf('xy    = [%d %d %d %d]\n', xy);
    fprintf('ROI边长 = %d (预期 >= 60)\n', xy(3)-xy(1)+1);

    % ---- 验证新参数: 传入更大的下限应放大ROI ----
    [~, ~, ~, xy2] = detectLaserSpotRobust(roiImage, 120);
    roiSize2 = xy2(3)-xy2(1)+1;
    fprintf('下限120时 ROI边长 = %d (预期 >= 120)\n', roiSize2);

    % ---- 验证下限0: 不设下限 ----
    [~, ~, ~, xy3] = detectLaserSpotRobust(roiImage, 0);
    fprintf('下限0时 ROI边长 = %d\n', xy3(3)-xy3(1)+1);

    % ---- 断言 ----
    posErr = norm(wCent - [200, 200]);
    assert(posErr < 25, ['质心偏离真值过大: ', num2str(posErr)]);

    roiSize = xy(3) - xy(1) + 1;
    assert(roiSize >= 60, ['ROI缩小到', num2str(roiSize), '，正反馈缩小未阻止']);

    assert(area > 500, ['面积过小: ', num2str(area), '，可能选中小散斑亮核']);

    assert(roiSize2 >= 120, ['下限120未生效: ', num2str(roiSize2)]);

    fprintf('\n[PASS] 散斑场景：选整块光斑、ROI未缩小、质心正确、下限参数生效\n');
end
