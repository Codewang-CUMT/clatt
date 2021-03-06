function [x] = bmap(x, xprior,Pprior,  nsteps, dt, nR, v_m, omega_m, sigma_v, sigma_w, nT, dim_target,PHIT, QTd, zr, Rr,  zt, Rt, zl, Rl, nL)
% % batch MAP for CLATT (cooperative localization and target tracking)


%% parameters/constants
global gRB
J = [0 -1; 1 0];
epsilon = 1e-4;
itermax = 20; %max number of iterations

nddt = 3;
ddt = dt/nddt;
Q = [ sigma_v^2 0; 0 sigma_w^2 ]; %odometry noise

dofR = 3*nR;
dofT = dim_target*nT;
dofk = dofR+dofT;

% % first robot state is known, so excluded from the state, while first target state has prior!
% state = [robots-targets; robots-targets;...]
x0 = x(1:dofR,1);
x = x(dofR+1:end,1);


%% Gauss-Newton
for iter = 1:itermax
    
    ndim = dofT + dofk*(nsteps-1); %first robot pose is known, hence not included in the state
    if gRB==3
        nmeas = dofT + 3*nR*(nsteps-1)+dim_target*nT*(nsteps-1)  + 2*nR*nR* (nsteps-1) + 2*nR*nT*(nsteps-1);  %may be converative!!!
    else
        nmeas = dofT + 3*nR*(nsteps-1)+dim_target*nT*(nsteps-1)  + nR*nR* (nsteps-1) + nR*nT*(nsteps-1);  %may be converative!!!
    end
    
    A = sparse(nmeas, ndim); %jacobian
    b = zeros(nmeas,1); %residual
    
    % % prior for the first target's state
    xTprior = xprior(3*nR+[1:dofT],1);
    PTprior = Pprior(3*nR+[1:dofT] , 3*nR+[1:dofT]);
    sqrtQk =  real(sqrtm(inv(PTprior)));
    ak = xTprior - x(1:dofT,1);
    Gk = eye(dofT);
    
    indt2 = 1:dofT;
    indxm = 1:dofT;
    
    b(indxm,1) = sqrtQk'*ak ;
    A(indxm, indt2) = sqrtQk'*Gk ;
    
    % % all measurements
    for k = 2:nsteps %because first robot pose is known
        
        % % proprioception measurements % %
        % robot propagation
        for ell = 1:nR
            if k==2 %this actuall is the first robot in the state
                x1k = x0(3*ell-2:3*ell,1); %xprior(3*ell-2:3*ell,1); %x0 should be same as xprior
                P1k = zeros(3);
                for i=1:nddt
                    xk = [ x1k(1) + v_m(ell,k-1)*ddt*cos(x1k(3));
                        x1k(2) + v_m(ell,k-1)*ddt*sin(x1k(3));
                        pi_to_pi(x1k(3) + omega_m(ell,k-1)*ddt) ];
                    F1k = [ 1 0 -v_m(ell,k-1)*ddt*sin(x1k(3));
                        0 1  v_m(ell,k-1)*ddt*cos(x1k(3));
                        0 0   1 ];
                    Gk = [ ddt*cos(x1k(3))   0;
                        ddt*sin(x1k(3))   0;
                        0     ddt ];
                    P1k = F1k*P1k*F1k'+Gk*Q*Gk';
                    x1k = xk;
                end
                Qk = P1k;
                %sqrtQk = real(sqrtm(inv(Qk)));
                L = chol(Qk,'lower');
                invQk = (L'\eye(size(L)))*(L\eye(size(L)));
                sqrtQk = sqrtm(invQk);
                
                indr2 = dofT + [3*ell-2:3*ell];
                indxm =dofT + [3*ell-2:3*ell ];
                
                Fk =  - eye(3);
                ak = x(indr2,1) - xk;
                ak(3) = pi_to_pi(ak(3));
                
                b(indxm,1) = sqrtQk'*ak ;
                A(indxm,indr2) = sqrtQk'*Fk ;
                
            elseif k>2
                indr1 =  dofT + dofk*(k-3)+ [3*(ell)-2 : 3*(ell)] ;  %note the first pose (k=1) is excluded in x, i.e., x_k actually corresponds to xinit_k+1
                
                x1k = x(indr1,1);
                P1k = zeros(3);
                for i=1:nddt
                    xk = [ x1k(1) + v_m(ell,k-1)*ddt*cos(x1k(3));
                        x1k(2) + v_m(ell,k-1)*ddt*sin(x1k(3));
                        pi_to_pi(x1k(3) + omega_m(ell,k-1)*ddt) ]; %note the odometry actually is from time k
                    F1k = [1 0 -v_m(ell,k-1)*ddt*sin(x1k(3));
                        0 1  v_m(ell,k-1)*ddt*cos(x1k(3));
                        0 0   1];
                    Gk = [ddt*cos(x1k(3))   0;
                        ddt*sin(x1k(3))   0;
                        0     ddt];
                    P1k = F1k*P1k*F1k'+Gk*Q*Gk';
                    x1k = xk;
                end
                Qk = P1k;
                L = chol(Qk,'lower');
                invQk = (L'\eye(size(L)))*(L\eye(size(L)));
                sqrtQk = sqrtm(invQk);
                
                indr2 =  dofT + dofk*(k-2)+[3*(ell)-2 : 3*(ell)] ;
                indxm =  dofT + dofk*(k-2)+[ 3*ell-2:3*ell ];
                
                F1k =  [ eye(2)   J*(x(indr2(1:2),1)-x(indr1(1:2),1));   zeros(1,2)  1 ];%beware of sign
                Fk = - eye(3);
                ak = x(indr2,1) - xk;
                ak(3) = pi_to_pi(ak(3));
                
                b(indxm,1) = sqrtQk'*ak ;
                A(indxm,indr1) = sqrtQk'*F1k ;
                A(indxm,indr2) = sqrtQk'*Fk ;
            end
        end
        
        
        % target propagation
        for ell = 1:nT
            indt1 =  dofT + dofk*(k-3)+ 3*nR +[dim_target*(ell-1)+1:dim_target*ell];
            indt2 =  dofT + dofk*(k-2)+ 3*nR +[dim_target*(ell-1)+1:dim_target*ell];
            
            F1k = PHIT(:,:,ell,k-1); 
            Gk = - eye(dim_target);
            ak = x(indt2,1) - F1k*x(indt1,1);
            L = chol(QTd(:,:,ell,k-1),'lower');
            invQk = (L'\eye(size(L)))*(L\eye(size(L)));
            sqrtQk = sqrtm(invQk);
            
            indxm =  dofT + dofk*(k-2)+ 3*nR +[dim_target*(ell-1)+1:dim_target*ell];
            
            b(indxm,1) = sqrtQk'*ak ;
            A(indxm, indt1) = sqrtQk'*F1k ;
            A(indxm, indt2) = sqrtQk'*Gk ;
        end
        
        
        
        % % exterocpetive measurements % %
        % robot-to-robot
        imeas = 0;
        for ell = 1:nR
            for i = 1:size(zr(ell,:,:,k),3)
                if zr(ell,3,i,k)<=0, continue, end
                
                Ri = Rr{ell,k}(2*i-1:2*i, 2*i-1:2*i);
                sqrtRk = sqrtm(inv(Ri));
                
                imeas = imeas+1;
                indr1 =  dofT + dofk*(k-2)+[3*ell-2:3*ell];
                indr2 =  dofT + dofk*(k-2)+[3*zr(ell,3,i,k)-2 : 3*zr(ell,3,i,k)];
                
                C = [cos(x(indr1(3))) -sin(x(indr1(3)));  sin(x(indr1(3))) cos(x(indr1(3))) ];
                i_p_r = C'*(x(indr2(1:2))-x(indr1(1:2)));
                rho = norm(i_p_r);
                th = atan2(i_p_r(2),i_p_r(1));
                zhat = [rho; th];
                
                if gRB==3
                    indxm =  dofT + dofk*(nsteps-1) + 2*nR*nR*(k-2) + [ 2*imeas-1:2*imeas ] ;
                    r =  [ zr(ell,1,i,k)-zhat(1,1);  pi_to_pi(zr(ell,2,i,k)-zhat(2,1))  ] ; %beware of sign
                    Htem = [ 1/norm(i_p_r)*i_p_r'; 1/norm(i_p_r)^2*i_p_r'*J' ];
                    H1 = - Htem* C'*[ eye(2)  J*(x(indr2(1:2)) - x(indr1(1:2))) ];
                    H2 = Htem* C'*[eye(2) zeros(2,1)];
                elseif gRB==2
                    indxm =  dofT + dofk*(nsteps-1) + nR*nR*(k-2) + imeas ;
                    r =  pi_to_pi(zr(ell,2,i,k)-zhat(2,1)); %beware of sign
                    Htem = [ 1/norm(i_p_r)*i_p_r'; 1/norm(i_p_r)^2*i_p_r'*J' ];
                    H1 = - Htem* C'*[ eye(2)  J*(x(indr2(1:2)) - x(indr1(1:2))) ];
                    H2 = Htem* C'*[eye(2) zeros(2,1)];
                    H1 = H1(2,:);
                    H2 = H2(2,:);
                    sqrtRk = sqrtRk(2,2);
                elseif gRB==1
                    indxm =  dofT + dofk*(nsteps-1) + nR*nR*(k-2) + imeas ;
                    r =  zr(ell,1,i,k)-zhat(1,1); %beware of sign
                    Htem = [ 1/norm(i_p_r)*i_p_r'; 1/norm(i_p_r)^2*i_p_r'*J' ];
                    H1 = - Htem* C'*[ eye(2)  J*(x(indr2(1:2)) - x(indr1(1:2))) ];
                    H2 = Htem* C'*[eye(2) zeros(2,1)];
                    H1 = H1(1,:);
                    H2 = H2(1,:);
                    sqrtRk = sqrtRk(1,1);
                end
                
                A(indxm, [indr1, indr2])  = [sqrtRk'*H1 , sqrtRk'*H2] ;
                b(indxm,1) = sqrtRk'*r;
            end
        end
        
        
        % robot-to-target
        imeas = 0;
        for ell = 1:nR
            for i = 1:size(zt(ell,:,:,k),3)
                if zt(ell,3,i,k)<=0, continue, end
                
                Ri = Rt{ell,k}(2*i-1:2*i, 2*i-1:2*i);
                sqrtRk = sqrtm(inv(Ri));
                
                imeas = imeas+1;
                indr1 =  dofT + dofk*(k-2)+ [3*ell-2:3*ell];
                indr2 =  dofT + dofk*(k-2)+ 3*nR+ [dim_target*(zt(ell,3,i,k)-1)+1 : dim_target*zt(ell,3,i,k)];
                
                C = [cos(x(indr1(3))) -sin(x(indr1(3)));  sin(x(indr1(3))) cos(x(indr1(3))) ];
                i_p_t = C'*(x(indr2(1:2))-x(indr1(1:2)));
                rho = norm(i_p_t);
                th = atan2(i_p_t(2),i_p_t(1));
                zhat = [rho; th];
                
                if gRB==3
                    indxm =  dofT + dofk*(nsteps-1) + 2*nR*nR*(nsteps-1) + 2*nR*nT*(k-2) + [2*imeas-1:2*imeas] ;
                    r =  [ zt(ell,1,i,k)-zhat(1,1);  pi_to_pi(zt(ell,2,i,k)-zhat(2,1))  ] ; %beware of sign
                    Htem = [ 1/norm(i_p_t)*i_p_t'; 1/norm(i_p_t)^2*i_p_t'*J' ];
                    H1 = - Htem* C'*[ eye(2)  J*(x(indr2(1:2)) - x(indr1(1:2))) ];
                    H2 = Htem* C'*[eye(2) zeros(2,dim_target-2)];
                elseif gRB==2
                    indxm =  dofT + dofk*(nsteps-1) + nR*nR*(nsteps-1) + nR*nT*(k-2) + imeas ;
                    r =  pi_to_pi(zt(ell,2,i,k)-zhat(2,1)) ; %beware of sign
                    Htem = [ 1/norm(i_p_t)*i_p_t'; 1/norm(i_p_t)^2*i_p_t'*J' ];
                    H1 = - Htem* C'*[ eye(2)  J*(x(indr2(1:2)) - x(indr1(1:2))) ];
                    H2 = Htem* C'*[eye(2) zeros(2,dim_target-2)];
                    H1 = H1(2,:);
                    H2 = H2(2,:);
                    sqrtRk = sqrtRk(2,2);
                elseif gRB==1
                    indxm =  dofT + dofk*(nsteps-1) + nR*nR*(nsteps-1) + nR*nT*(k-2) +imeas ;
                    r =  zt(ell,1,i,k)-zhat(1,1);  %beware of sign
                    Htem = [ 1/norm(i_p_t)*i_p_t'; 1/norm(i_p_t)^2*i_p_t'*J' ];
                    H1 = - Htem* C'*[ eye(2)  J*(x(indr2(1:2)) - x(indr1(1:2))) ];
                    H2 = Htem* C'*[eye(2) zeros(2,dim_target-2)];
                    H1 = H1(1,:);
                    H2 = H2(1,:);
                    sqrtRk = sqrtRk(1,1);
                end
                
                A(indxm, [indr1, indr2])  = [sqrtRk'*H1 , sqrtRk'*H2] ;
                b(indxm,1) = sqrtRk'*r;
            end
        end
        
        % robot-to-landmark
        
        
    end%k
    

    % % solve linear system : Ax = b
    % % using sparse QR with reordering
    [~,n] = size(A);
    [V,beta,p,R,qp] = cs_qr(A) ; % fill-in reduced reordering qp
    d = cs_qleft(V, beta, p, b) ;
    Rp = R(1:n,1:n);
    bp = d(1:n,1);
    delta_x =  Rp \ bp;
    delta_x(qp) = delta_x ;
    
    
    x = x + delta_x;
    
    ndx = norm(delta_x);
    if ndx<epsilon, break, end
    
end%end iteration

% % augment the first robot/target state
x = [x0; x];

