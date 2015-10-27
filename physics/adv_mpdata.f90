!> ----------------------------------------------------------------------------
!!
!!  The MPDATA advection scheme
!!  Not fully implemented / translated from python yet
!!
!!  Author: Ethan Gutmann (gutmann@ucar.edu)
!!
!! ----------------------------------------------------------------------------
module adv_mpdata
    use data_structures
    use string
    use output
    
    implicit none
    private
    real,dimension(:,:,:),allocatable::U_m,V_m,W_m
    integer :: order
    integer :: timestep
    public:: mpdata, mpdata_init
    public:: advect_u, advect_w, advect_v, advect3d ! for test_mpdata testing only!
    

contains
    subroutine flux2(l,r,U,nx,nz,ny,f)
    !     Calculate the donor cell flux function
    !     l = left gridcell scalar 
    !     r = right gridcell scalar
    !     U = Courant number (u*dt/dx)
    !     
    !     If U is positive, return l*U if U is negative return r*U
    !     By using the mathematical form instead of the logical form, 
    !     we can run on the entire grid simultaneously, and avoid branches

    !   arguments
        implicit none
        real, dimension(1:nx,1:nz,1:ny), intent(in) :: l,r,U
        real, dimension(1:nx,1:nz,1:ny), intent(inout) :: f
        integer,intent(in) :: ny,nz,nx
        !   internal parameter
        integer ::  err,i!,j,Ny,Nz,Nx
        !   main code
        f= ((U+ABS(U)) * l + (U-ABS(U)) * r)/2

    end subroutine flux2

    subroutine flux1(l,r,U,f)
    !     Calculate the donor cell flux function
    !     l = left gridcell scalar 
    !     r = right gridcell scalar
    !     U = Courant number (u*dt/dx)
    !     
    !     If U is positive, return l*U if U is negative return r*U
    !     By using the mathematical form instead of the logical form, 
    !     we can run on the entire grid simultaneously, and avoid branches

    !   arguments
        implicit none
        real, dimension(:), intent(in) :: l,r,U
        real, dimension(:), intent(inout) :: f
        
        !   main code
        f= ((U+ABS(U)) * l + (U-ABS(U)) * r)/2

    end subroutine flux1

    subroutine advect2d(q,u,v,rho,dz,nx,nz,ny,options)
!     horizontally advect a scalar q by wind field (u,v)
!     q = input scalar field (e.g. cloud water [kg])
!     u,v = horizontal and vertical wind speeds [m/s] on a staggered grid. normalized by dt/dx
!     
!     Algorithm from MPDATA: 
!         Smolarkiewicz, PK and Margolin, LG (1998)
!             MPDATA: A Finite-Differnce Solver for Geophysical Flows
!             Journal of Computational Physics 140, p459-480. CP985901
        real,dimension(:,:,:), intent(inout) :: q,u,v,rho,dz
        integer,intent(in)::nx,nz,ny
        type(options_type),intent(in) :: options
        
!     # The above calculation is just the standard upwind formulations
!     # below, calculate the diffusivity correction term of MPDATA
!     # f=np.double(0.5)
!     # 
!     # # define A,B [l,r,u,b] (see MPDATA review reference)
!     # # l,r,u,b = left, right, upper, bottom edges of the grid cells
!     # Al=(q1(1:-1,:-2)-q1(1:-1,1:-1))/(q1(1:-1,:-2)+q1(1:-1,1:-1))
!     # Ar=(q1(1:-1,2:)-q1(1:-1,1:-1))/(q1(1:-1,2:)+q1(1:-1,1:-1))
!     # Au=(q1(:-2,1:-1)-q1(1:-1,1:-1))/(q1(:-2,1:-1)+q1(1:-1,1:-1))
!     # Ab=(q1(2:,1:-1)-q1(1:-1,1:-1))/(q1(2:,1:-1)+q1(1:-1,1:-1))
!     # 
!     # q11=q1(2:,2:)+q1(2:,1:-1)
!     # Br=0.5*((q11-q1(:-2,2:)-q1(:-2,1:-1))
!     #     /(q11+q1(:-2,2:)+q1(:-2,1:-1)))
!     # q11=q1(2:,:-2)+q1(2:,1:-1)
!     # Bl=0.5*((q11-q1(:-2,:-2)-q1(:-2,1:-1))
!     #     /(q11+q1(:-2,:-2)+q1(:-2,1:-1)))
!     # q11=q1(:-2,2:)+q1(1:-1,2:)
!     # Bu=0.5*((q11-q1(:-2,:-2)-q1(1:-1,:-2))
!     #     /(q11+q1(:-2,:-2)+q1(1:-1,:-2)))
!     # q11=q1(2:,2:)+q1(1:-1,2:)
!     # Bb=0.5*((q11-q1(2:,:-2)-q1(1:-1,:-2))
!     #     /(q11+q1(2:,:-2)+q1(1:-1,:-2)))
!     # 
!     # # compute diffusion correction U/V terms (see MPDATA review reference)
!     # Uabs=np.abs(U)
!     # # first find U/V terms on the grid cell borders
!     # curUabs=(Uabs[1:-1,:-2)+Uabs[1:-1,1:-1))/2
!     # curU=Ux0
!     # curV=(V[1:-1,:-2)+V[1:-1,1:-1))/2
!     # # then compute Ul
!     # Ul=curUabs*(1-curUabs)*Al - 2*f*curU*curV*Bl
!     # # compute Ur using the same two steps
!     # curUabs=(Uabs[1:-1,2:)+Uabs[1:-1,1:-1))/2
!     # curU=Ux1
!     # curV=(V[1:-1,2:)+V[1:-1,1:-1))/2
!     # Ur=curUabs*(1-curUabs)*Ar - 2*f*curU*curV*Br
!     # # compute Vu
!     # Vabs=np.abs(V)
!     # curVabs=(Vabs[:-2,1:-1)+Vabs[1:-1,1:-1))/2
!     # curV=Vy0
!     # curU=(U[:-2,1:-1)+U[1:-1,1:-1))/2
!     # Vu=curVabs*(1-curVabs)*Bu - 2*f*curU*curV*Bu
!     # # compute Vb
!     # curVabs=(Vabs[2:,1:-1)+Vabs[1:-1,1:-1))/2
!     # curV=Vy1
!     # curU=(U[2:,1:-1)+U[1:-1,1:-1))/2
!     # Vb=curVabs*(1-curVabs)*Bb - 2*f*curU*curV*Bb
!     # 
!     # q[1:-1,1:-1)=(q1(1:-1,1:-1)
!     #     -(F(q1(1:-1,1:-1),q1(1:-1,2:),Ul)
!     #     -F(q1(1:-1,:-2),q1(1:-1,1:-1),Ur))
!     #     -(F(q1(1:-1,1:-1),q1(2:,1:-1),Vu)
!     #     -F(q1(:-2,1:-1),q1(1:-1,1:-1),Vb)))
    end subroutine advect2d

    subroutine advect_w(q,u,nx,n,ny, FCT)
        real,dimension(:,:,:), intent(inout) :: q
        real,dimension(:,:,:), intent(in) :: u
        integer,intent(in)::n,nx,ny
        logical, intent(in):: FCT ! use Flux Corrected Transport 
        ! these are terms needed in the FCT scheme
        real :: qmax_i, qmin_i, qmax_i2, qmin_i2
        real :: beta_in_i, beta_out_i, beta_in_i2, beta_out_i2
        real :: fin_i, fout_i, fin_i2, fout_i2
        integer :: i
        
        real,dimension(n)::q1
        real,dimension(n-1)::f,l,r,U2, denom
!         real,dimension(n-2)::fl,fr, l2,c2,r2, U3, denom, Vl, Vr
        integer::y, x
        
        do y=2,ny-1
            do x=2,nx-1
                l  = q(x,1:n-1,y)
                r  = q(x,2:n,y)
                U2 = u(x,1:n-1,y)
                
                ! This is the core 1D implementation of mpdata
                ! advect_w requires its own implementation to handle the top and bottom boundaries
                call flux1(l,r,U2,f)
                
                ! for advect_w we need to add the fluxes to the top and bottom boundaries too. 
                q1(1)=l(1)-f(1)
                ! note inlined flux1 call for the top boundary condition
                q1(n)=r(n-1)+f(n-1) - &
                        ((u(x,n,y)+ABS(u(x,n,y))) * r(n-1) + (u(x,n,y)-ABS(u(x,n,y))) * r(n-1))/2
                
                q1(2:n-1) = l(2:n-1) + (f(1:n-2) - f(2:n-1))

                ! This is the core 1D implementation of MPDATA correction
                
                ! This is the MPDATA diffusion correction term for 1D flow
                ! U is defined on the mass grid for the pseudo-velocities?
                ! left and right pseudo (diffusive) velocities
    
                ! we will copy the q1 data into r to potentially minimize aliasing problems 
                ! for the compiler, and improve memory alignment for vectorization
                r  = q1(2:n) 
                ! l  = q1(1:n-1) ! no need to copy these data over again
    
                ! In MPDATA papers (r-l)/(r+l) is usually refered to as "A"
                ! compute the denomenator first so we can check that it is not zero
                denom=(r + q1(1:n-1))
                where(denom==0) denom=1e-10
                ! U2 is the diffusive pseudo-velocity
                U2 = abs(U2) - U2**2
                U2 = U2 * (r-q1(1:n-1)) / denom
    
                ! now calculate the MPDATA flux term
                call flux1(q1(1:n-1),r,U2,f)
                
                if (FCT) then
                    ! This is the Flux Corrected Transport option described in : 
                    ! Smolarkiewicz and Grabowski (1990) J. of Comp. Phys. v86 p355-375

                    ! for now at least this is one in a loop instead of vectorized.  I'm not sure how easy this would be to vectorize. 
                    do i=1,n-1
                        ! first find the min and max values allowable in the final field based on the initial (stored in l) and upwind (q1) fields
                        ! min and max are taken from the grid cells on either side of the flux cell wall to be corrected
                        if (i==1) then
                            ! l still equals q0
                            qmax_i=max(q1(i),q1(i+1),l(i),l(i+1))
                            qmin_i=min(q1(i),q1(i+1),l(i),l(i+1))
                            qmax_i2=max(q1(i),q1(i+1),q1(i+2),l(i),l(i+1),l(i+2))
                            qmin_i2=min(q1(i),q1(i+1),q1(i+2),l(i),l(i+1),l(i+2))
                        elseif (i/=(n-1)) then
                            ! l still equals q0
                            qmax_i=qmax_i2
                            qmin_i=qmin_i2
                            qmax_i2=max(q1(i),q1(i+1),q1(i+2),l(i),l(i+1),l(i+2))
                            qmin_i2=min(q1(i),q1(i+1),q1(i+2),l(i),l(i+1),l(i+2))
                        else
                            ! for the boundary, q1(i+1)==q0(i+1), l is only 1:n-1
                            qmax_i=qmax_i2
                            qmin_i=qmin_i2
                            qmax_i2=max(q1(i),q1(i+1),l(i))
                            qmin_i2=min(q1(i),q1(i+1),l(i))
                        endif
    
                        ! next compute the total fluxes into and out of the upwind and downwind cells
                        ! these are the fluxes into and out of the "left-hand" cell (which is just the previous "right-hand" cell)
                        if (i/=1) then
                            fin_i  = fin_i2
                            fout_i = fout_i2
                        else
                            ! Need to apply flux limitations for bottom cell in advect_w (not in horizontal advection)
                            fin_i  = 0 - min(0.,f(i))
                            fout_i = max(0.,f(i))
                        endif
    
                        ! these are the fluxes into and out of the "right-hand" cell
                        if (i/=(n-1)) then
                            fin_i2 = max(0.,f(i)) - min(0.,f(i+1))
                            fout_i2 = max(0.,f(i+1)) - min(0.,f(i))
                        else
                            ! Need to apply flux limitations for top cell in advect_w (not in horizontal advection)
                            fin_i2  = max(0.,f(i))
                            fout_i2 = max(0.,f(i))
                        endif
    
                        ! if wind is left to right we limit based on flow out of the left cell and into the right cell
                        if (U2(i)>0) then
                            beta_out_i = (q1(i)-qmin_i) / (fout_i+1e-15)
                            beta_in_i2 = (qmax_i2-q1(i+1)) / (fin_i2+1e-15)
            
                            U2(i) = min(1.,beta_in_i2, beta_out_i) * U2(i)
            
                        ! if wind is right to left we limit based on flow out of the right cell and into the left cell
                        elseif (U2(i)<0) then
                            beta_in_i = (qmax_i-q1(i)) / (fin_i+1e-15)
                            beta_out_i2 = (q1(i+1)-qmin_i2) / (fout_i2+1e-15)
            
                            U2(i) = min(1.,beta_in_i, beta_out_i2) * U2(i)
                        endif
                    end do
                    ! now re-calculate the MPDATA flux term after applying the FCT to U2
                    call flux1(q1(1:n-1),r,U2,f)
                
                endif
                
                q(x,2:n-1,y) = q1(2:n-1) + (f(1:n-2) - f(2:n-1))
                q(x,1,y) = q1(1) - f(1)
                q(x,n,y) = q1(n) + f(n-1) 
                ! note we don't subtract diffusive fluxes out the top as the layer above it is presumed to be the same
                ! as a result the diffusion pseudo-velocity term would be 0
            enddo
        enddo
    end subroutine advect_w

    subroutine advect_v(q,u,nx,nz,n, FCT)
        real,dimension(:,:,:), intent(inout) :: q
        real,dimension(:,:,:), intent(in) :: u
        integer,intent(in)::n,nz,nx
        
        logical, intent(in):: FCT ! use Flux Corrected Transport 
        ! these are terms needed in the FCT scheme
        real :: qmax_i, qmin_i, qmax_i2, qmin_i2
        real :: beta_in_i, beta_out_i, beta_in_i2, beta_out_i2
        real :: fin_i, fout_i, fin_i2, fout_i2
        integer :: i,y
        
        real,dimension(n)::q1
        real,dimension(n-1)::f,l,r,U2, denom
        integer::x, z
        logical::flux_is_w=.False.

        
        ! might be more cache friendly if we tile over x? 
        ! though that won't work with including mpdata_core
        do z=1,nz
            do x=2,nx-1
                l  = q(x,z,1:n-1)
                r  = q(x,z,2:n)
                U2 = u(x,z,1:n-1)
                
                include 'adv_mpdata_core.f90'
                
                if (FCT) then
                    include 'adv_mpdata_FCT_core.f90'
                    ! now re-calculate the MPDATA flux term after applying the FCT to U2
                    call flux1(q1(1:n-1),r,U2,f)
                endif
                
                q(x,z,2:n-1) = q1(2:n-1) + (f(:n-2) - f(2:n-1))
            enddo
        enddo
    end subroutine advect_v

    subroutine advect_u(q,u,n,nz,ny, FCT)
        real,dimension(:,:,:), intent(inout) :: q
        real,dimension(:,:,:), intent(in) :: u
        integer,intent(in)::n,nz,ny
        logical, intent(in):: FCT ! use Flux Corrected Transport 
        ! these are terms needed in the FCT scheme
        real :: qmax_i, qmin_i, qmax_i2, qmin_i2
        real :: beta_in_i, beta_out_i, beta_in_i2, beta_out_i2
        real :: fin_i, fout_i, fin_i2, fout_i2
        integer :: i,x
        
        real,dimension(n)::q1
        real,dimension(n-1)::f,l,r,U2, denom
        integer::y, z
        logical::flux_is_w=.False.
        
        ! this is just a flag for the FCT code
        x=-1
        ! loop over internal y columns
        do y=2,ny-1
            ! loop over all z layers
            do z=1,nz
                
                ! copy the data into local (cached) variables.  Makes the include mpdata_core possible
                l  = q(1:n-1,z,y)
                r  = q(2:n,z,y)
                U2 = u(1:n-1,z,y)

                include 'adv_mpdata_core.f90'
                
                if (FCT) then
                    include 'adv_mpdata_FCT_core.f90'
                    ! now re-calculate the MPDATA flux term after applying the FCT to U2
                    call flux1(q1(1:n-1),r,U2,f)
                endif
                    
                
                q(2:n-1,z,y) = q1(2:n-1) + (f(:n-2) - f(2:n-1))
            enddo
        enddo
    end subroutine advect_u
    
    subroutine upwind_advection(q, u, v, w, q2, nx,nz,ny)
        implicit none
        real,dimension(1:nx,1:nz,1:ny),  intent(in) :: q
        real,dimension(1:nx-1,1:nz,1:ny),intent(in) :: u
        real,dimension(1:nx,1:nz,1:ny-1),intent(in) :: v
        real,dimension(1:nx,1:nz,1:ny),  intent(in) :: w
        real,dimension(1:nx,1:nz,1:ny),  intent(inout) :: q2
        integer, intent(in) :: ny,nz,nx
        
        ! interal parameters
        integer :: i
        real, dimension(1:nx-1,1:nz) :: f1 ! there used to be an f2 to store f[x+1]
        real, dimension(1:nx-2,1:nz) :: f3,f4
        real, dimension(1:nx-2,1:nz-1) ::f5
        !$omp parallel shared(q2,q,u,v,w) firstprivate(nx,ny,nz) private(i,f1,f3,f4,f5)
        !$omp do schedule(static)
        do i=1,ny
            if ((i==1).or.(i==ny)) then
                q2(:,:,i)=q(:,:,i)
            else
                q2(1,:,i)=q(1, :,i)
                q2(nx,:,i)=q(nx, :,i)
                
!           by manually inlining the flux2 call we should remove extra array copies that the compiler doesn't remove. 
!           equivalent flux2 calls are left in for reference (commented) to restore recall that f1,f3,f4... arrays should be 3D : n x m x 1
!           calculate fluxes between grid cells
!            call flux2(q(1:nx-1,:,i),     q(2:nx,:,i),     u(1:nx-1,:,i),     nx-1,nz,  1,f1)  ! f1 = Ux0 and Ux1
!            call flux2(q(2:nx-1,:,i),     q(2:nx-1,:,i+1), v(2:nx-1,:,i),     nx-2,nz,  1,f3)  ! f3 = Vy1
!            call flux2(q(2:nx-1,:,i-1),   q(2:nx-1,:,i),   v(2:nx-1,:,i-1),   nx-2,nz,  1,f4)  ! f4 = Vy0
!            call flux2(q(2:nx-1,1:nz-1,i),q(2:nx-1,2:nz,i),w(2:nx-1,1:nz-1,i),nx-2,nz-1,1,f5)  ! f5 = Wz0 and Wz1
               f1= ((u(1:nx-1,:,i)      + ABS(u(1:nx-1,:,i)))      * q(1:nx-1,:,i) + &
                    (u(1:nx-1,:,i)      - ABS(u(1:nx-1,:,i)))      * q(2:nx,:,i))/2
               f3= ((v(2:nx-1,:,i)      + ABS(v(2:nx-1,:,i)))      * q(2:nx-1,:,i) + &
                    (v(2:nx-1,:,i)      - ABS(v(2:nx-1,:,i)))      * q(2:nx-1,:,i+1))/2
               f4= ((v(2:nx-1,:,i-1)    + ABS(v(2:nx-1,:,i-1)))    * q(2:nx-1,:,i-1) + &
                    (v(2:nx-1,:,i-1)    - ABS(v(2:nx-1,:,i-1)))    * q(2:nx-1,:,i))/2
               f5= ((w(2:nx-1,1:nz-1,i) + ABS(w(2:nx-1,1:nz-1,i))) * q(2:nx-1,1:nz-1,i) + &
                    (w(2:nx-1,1:nz-1,i) - ABS(w(2:nx-1,1:nz-1,i))) * q(2:nx-1,2:nz,i))/2
           
               ! perform horizontal advection
               q2(2:nx-1,:,i)=q(2:nx-1,:,i) - ((f1(2:nx-1,:)-f1(1:nx-2,:)) + (f3(:,:)-f4(:,:)))
               ! then vertical (order doesn't matter because fluxes f1-6 are calculated before applying them)
               ! add fluxes to middle layers
               q2(2:nx-1,2:nz-1,i)=q2(2:nx-1,2:nz-1,i)-(f5(:,2:nz-1)-f5(:,1:nz-2))
               ! add fluxes to bottom layer
               q2(2:nx-1,1,i)=q2(2:nx-1,1,i)-f5(:,1)
               ! add fluxes to top layer
               q2(2:nx-1,nz,i)=q2(2:nx-1,nz,i)-(q(2:nx-1,nz,i)*w(2:nx-1,nz,i)-f5(:,nz-1))
           endif
        enddo
        !$omp end do
        !$omp end parallel
        
    end subroutine upwind_advection

    subroutine mpdata_fluxes(q,u,v,w,u2,v2,w2, nx,nz,ny)
        implicit none
        real, dimension(nx,nz,ny),   intent(in) :: q,w
        real, dimension(nx-1,nz,ny), intent(in) :: u
        real, dimension(nx,nz,ny-1), intent(in) :: v
        real, dimension(nx-1,nz,ny), intent(out) :: u2
        real, dimension(nx,nz,ny-1), intent(out) :: v2
        real, dimension(nx,nz,ny),   intent(out) :: w2
        integer, intent(in) :: nx,ny,nz
        
        real, dimension(nx-1) :: rx, lx, denomx
        real, dimension(nx) :: r, l, denom
        integer :: i, j
        
        ! This might run faster if tiled over x and y to be more cache friendly. 
        !$omp parallel shared(q,u,v,w,u2,v2,w2) firstprivate(nx,ny,nz) &
        !$omp private(i,j, rx,lx,r,l, denomx,denom)
        !$omp do schedule(static)
        do i=1,ny
            do j=1,nz
                ! -----------------------
                ! First compute the U component
                ! -----------------------
                if ((i>1).and.(i<ny)) then
                    rx=q(2:nx,j,i)
                    lx=q(1:nx-1,j,i)
                    ! In MPDATA papers (r-l)/(r+l) is usually refered to as "A"
                    ! compute the denomenator first so we can check that it is not zero
                    denomx=(rx + lx)
                    where(denomx==0) denomx=1e-10
                    ! U2 is the diffusive pseudo-velocity
                    u2(:,j,i) = abs(u(:,j,i)) - u(:,j,i)**2
                    u2(:,j,i) = u2(:,j,i) * (rx-lx) / denomx
                else
                    u2(:,j,i)=0
                endif
                

                ! next compute the V and W components
                if (i==1) then
                    w2(:,j,i)=0
                else
                    ! -----------------------
                    ! compute the V component
                    ! -----------------------
                    r=q(:,j,i)
                    l=q(:,j,i-1)
                    ! In MPDATA papers A = (r-l)/(r+l)
                    ! compute the denomenator first so we can check that it is not zero
                    denom=(r + l)
                    where(denom==0) denom=1e-10
                    ! U2 is the diffusive pseudo-velocity
                    v2(:,j,i-1) = abs(v(:,j,i-1)) - v(:,j,i-1)**2
                    v2(:,j,i-1) = v2(:,j,i-1) * (r-l) / denom
                    
                    
                    ! -----------------------
                    ! compute the w component
                    ! -----------------------
                    if (i==ny) then
                        w2(:,j,i)=0
                    else
                        if (j<nz) then
                            r=q(:,j+1,i)
                            l=q(:,j,i)
                            ! In MPDATA papers A = (r-l)/(r+l)
                            ! compute the denomenator first so we can check that it is not zero
                            denom=(r + l)
                            where(denom==0) denom=1e-10
                            ! U2 is the diffusive pseudo-velocity
                            w2(:,j,i) = abs(w(:,j,i)) - w(:,j,i)**2
                            w2(:,j,i) = w2(:,j,i) * (r-l) / denom
                        else
                            w2(:,j,i) = 0
                        endif
                    endif
                    
                endif
            end do
        end do
        !$omp end do
        !$omp end parallel
        
    end subroutine mpdata_fluxes

    subroutine flux_limiter(q, q2, u,v,w, nx,nz,ny)
        implicit none
        real,dimension(1:nx,1:nz,1:ny),  intent(in)    :: q, q2
        real,dimension(1:nx-1,1:nz,1:ny),intent(inout) :: u
        real,dimension(1:nx,1:nz,1:ny-1),intent(inout) :: v
        real,dimension(1:nx,1:nz,1:ny),  intent(inout) :: w
        integer, intent(in) :: nx,nz,ny
        
        integer :: i,j,k,n
        real, dimension(:), pointer :: q1, U2, l, f
        ! q1 = q after applying previous iteration advection
        ! l  = q before applying previous iteration
        ! U2 is the anti-diffusion pseudo-velocity
        ! f is the first pass calculation of MPDATA fluxes
        real, dimension(nx),   target :: q1x,lx
        real, dimension(nx-1), target :: fx, U2x
        real, dimension(ny),   target :: q1y,ly
        real, dimension(ny-1), target :: fy, U2y
        real, dimension(nz),   target :: q1z,lz
        real, dimension(nz-1), target :: fz, U2z
        logical :: flux_is_w
        
        real :: qmax_i,qmin_i,qmax_i2,qmin_i2
        real :: beta_in_i, beta_out_i, beta_in_i2, beta_out_i2
        real :: fin_i, fout_i, fin_i2, fout_i2
        
        ! NOTE: before inclusion of FCT_core the following variables must be setup: 
        ! q1 and l (l=q0)
        do j=2,ny-1
            flux_is_w=.False.
            n=nx
            q1=>q1x
            l =>lx
            U2=>U2x
            f=>fx
            do k=1,nz
                ! setup u
                q1=q2(:,k,j)
                U2=u(:,k,j)
                l =q(:,k,j)
                call flux1(q1(1:n-1),q1(2:n),U2,f)
                
                include "adv_mpdata_FCT_core.f90"
                u(:,k,j)=U2
            end do
            
            n=nz
            q1=>q1z
            l =>lz
            U2=>U2z
            f=>fz
            flux_is_w=.True.
            do k=2,nx-1
                ! setup w
                q1=q2(k,:,j)
                U2=w(k,1:n-1,j)
                l =q(k,:,j)
                call flux1(q1(1:n-1),q1(2:n),U2,f)
                ! NOTE: need to check this a little more
                include "adv_mpdata_FCT_core.f90"
                w(k,1:n-1,j)=U2
                w(k,n,j)=0
            end do
            
        end do
        
        flux_is_w=.False.
        n=ny
        q1=>q1y
        l =>ly
        U2=>U2y
        f=>fy
        ! NOTE: This it typically not the correct order for the loop variables
        ! but in this case it permits parallelization over a larger number (nx instead of nz)
        ! and because all data are copied from an oddly spaced grid regardless, it *probably* doesn't slow it down
        ! I'd like to re-write the v-flux delimiter to operate on all x simulataneously at some point...
        do j=1,nx
            do k=1,nz
                q1=q2(j,k,:)
                U2=v(j,k,:)
                l =q(j,k,:)
                call flux1(q1(1:n-1),q1(2:n),U2,f)
                
                include "adv_mpdata_FCT_core.f90"
                v(j,k,:)=U2
            end do
        end do
        
    end subroutine flux_limiter

    subroutine advect3d(q,u,v,w,rho,dz,nx,nz,ny,options, err)
        implicit none
        real,dimension(1:nx,1:nz,1:ny), intent(inout) :: q
        real,dimension(1:nx-1,1:nz,1:ny),intent(in) :: u
        real,dimension(1:nx,1:nz,1:ny-1),intent(in) :: v
        real,dimension(1:nx,1:nz,1:ny), intent(in) :: w
        real,dimension(1:nx,1:nz,1:ny), intent(in) :: rho
        real,dimension(1:nx,1:nz,1:ny), intent(in) :: dz
        integer, intent(in) :: ny,nz,nx
        type(options_type), intent(in)::options
        integer, intent(inout) :: err

        ! used for intermediate values in the mpdata calculation
        real,dimension(1:nx,1:nz,1:ny)   :: q2
        real,dimension(1:nx-1,1:nz,1:ny) :: u2
        real,dimension(1:nx,1:nz,1:ny-1) :: v2
        real,dimension(1:nx,1:nz,1:ny)   :: w2
        
        integer :: iord, i
        
        do iord=1,options%adv_options%mpdata_order
            if (iord==1) then
                call upwind_advection(q, u, v, w, q2, nx,nz,ny)
            else
                call mpdata_fluxes(q2, u, v, w, u2,v2,w2, nx,nz,ny)
        
                if (options%adv_options%flux_corrected_transport) then
                    call flux_limiter(q, q2, u2,v2,w2, nx,nz,ny)
                endif
                
                call upwind_advection(q2, u2, v2, w2, q, nx,nz,ny)
            endif
            
            ! 
            if (iord/=options%adv_options%mpdata_order) then
                if (iord>1) then
                    !$omp parallel shared(q,q2) firstprivate(ny) private(i)
                    !$omp do schedule(static)
                    do i=1,ny
                        q2(:,:,i)=q(:,:,i)
                    enddo
                    !$omp end do
                    !$omp end parallel
                endif
            else 
                if (iord==1) then
                    !$omp parallel shared(q,q2) firstprivate(ny) private(i)
                    !$omp do schedule(static)
                    do i=1,ny
                        q(:,:,i)=q2(:,:,i)
                    enddo
                    !$omp end do
                    !$omp end parallel
                endif
                
            endif
        end do
        

    end subroutine advect3d

    subroutine advect3d_old(q,u,v,w,rho,dz,nx,nz,ny,options, err)
        implicit none
        real,dimension(1:nx,1:nz,1:ny), intent(inout) :: q
        real,dimension(1:nx,1:nz,1:ny), intent(in) :: w
        real,dimension(1:nx-1,1:nz,1:ny),intent(in) :: u
        real,dimension(1:nx,1:nz,1:ny-1),intent(in) :: v
        real,dimension(1:nx,1:nz,1:ny), intent(in) :: rho
        real,dimension(1:nx,1:nz,1:ny), intent(in) :: dz
        integer, intent(in) :: ny,nz,nx
        type(options_type), intent(in)::options
        integer, intent(inout) :: err
        ! interal parameters
        integer :: i
        
        if (options%debug) then
            if (minval(q)<0) then
                write(*,*) minval(q)
                err=err-1
                where(q<0) q=0
            endif
!             if (maxval(q)>50000) then
!                 write(*,*) maxval(q)
!                 err=err-2
!                 where((q>50000)) q=50000 ! not sure what a realistic high value for number concentration is.
!             endif
            if (any(isnan(q))) then
                write(*,*) maxval(q)
                err=err-4
                where(isnan(q)) q=q(1,1,1) ! assumes the boundary point is a not crazy value
            endif
        endif
        
        
        ! perform an Alternating Direction Explicit MP-DATA time step
        ! but swap the order of the alternating directions with every call
        if (order==0) then
            call advect_u(q,u,nx,nz,ny, options%adv_options%flux_corrected_transport)
            call advect_v(q,v,nx,nz,ny, options%adv_options%flux_corrected_transport)
            call advect_w(q,w,nx,nz,ny, options%adv_options%flux_corrected_transport)
        elseif (order==1) then
            call advect_v(q,v,nx,nz,ny, options%adv_options%flux_corrected_transport)
            call advect_w(q,w,nx,nz,ny, options%adv_options%flux_corrected_transport)
            call advect_u(q,u,nx,nz,ny, options%adv_options%flux_corrected_transport)
        elseif (order==2) then
            call advect_w(q,w,nx,nz,ny, options%adv_options%flux_corrected_transport)
            call advect_u(q,u,nx,nz,ny, options%adv_options%flux_corrected_transport)
            call advect_v(q,v,nx,nz,ny, options%adv_options%flux_corrected_transport)
        endif
        
        if (options%adv_options%boundary_buffer) then
            ! smooth the very outer boundaries to try to minimize oscillatory behavior
            ! that can occur with MPDATA if the domain and boundaries are not in very good agreement
            q(2,:,:) = (q(1,:,:) + q(3,:,:))/2
            q(nx-1,:,:) = (q(nx,:,:) + q(nx-2,:,:))/2

            q(:,:,2) = (q(:,:,1) + q(:,:,3))/2
            q(:,:,ny-1) = (q(:,:,ny) + q(:,:,ny-2))/2
            ! for now top boundary is not processed because it is not read from data
        endif
        
        if (options%debug) then
            if (minval(q)<0) then
                if (err<0) err=0
                write(*,*) minval(q)
                if (minval(q)>(-1e-6)) then
                    where(q<0) q=0
                else
                    err=err+1
                endif
            endif
            if (maxval(q)>6000) then
                if (err<0) err=0
!                 write(*,*) maxval(q)
                err=err+2
            endif
            if (any(isnan(q))) then
                if (err<0) err=0
                write(*,*) maxval(q)
                err=err+4
            endif
        endif
    end subroutine advect3d_old
    
    subroutine mpdata_init(domain,options)
        type(domain_type), intent(inout) :: domain
        type(options_type), intent(in) :: options
        
        order    = 0
        timestep = 1 !just use for debugging
    end subroutine mpdata_init
    
!   primary entry point, advect all scalars in domain
    subroutine mpdata(domain,options,dt)
        implicit none
        type(domain_type),intent(inout)::domain
        type(options_type),intent(in)::options
        real,intent(in)::dt
        
        real::dx
        integer::nx,nz,ny,i, error
        
        dx=domain%dx
        nx=size(domain%dz,1)
        nz=size(domain%dz,2)
        ny=size(domain%dz,3)
        
!         call write_domain(domain,options,timestep,"mpdata_test"//trim(str(timestep))//".nc")
        timestep=timestep+1
!       if this if the first time we are called, we need to allocate the module level arrays
        if (.not.allocated(U_m)) then
            allocate(U_m(nx-1,nz,ny))
            allocate(V_m(nx,nz,ny-1))
            allocate(W_m(nx,nz,ny))
        endif
        
!       calculate U,V,W normalized for dt/dx
        if (options%advect_density) then
            U_m=domain%ur(2:nx,:,:)*(dt/dx**2)
            V_m=domain%vr(:,:,2:ny)*(dt/dx**2)
!           note, even though dz!=dx, W is computed from the divergence in U/V so it is scaled by dx/dz already
            W_m=domain%wr*(dt/dx**2)
        else
            U_m=domain%u(2:nx,:,:)*(dt/dx)
            V_m=domain%v(:,:,2:ny)*(dt/dx)
!           note, even though dz!=dx, W is computed from the divergence in U/V so it is scaled by dx/dz already
            W_m=domain%w*(dt/dx)
        endif
        
        error=0
        
!         print*, "qv"
        call advect3d(domain%qv,   U_m,V_m,W_m, domain%rho,domain%dz,nx,nz,ny,options, error)
        if (error/=0) then
            print*, "qv", error
            if (error>0) then
                stop "MPDATA Error"
            endif
        endif
        
        error=0
!         print*, "qc"
        call advect3d(domain%cloud,U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
        if (error/=0) then
            print*, "qc", error
            if (error>0) then
                stop "MPDATA Error"
            endif
        endif

        error=0
!         print*, "qr"
        call advect3d(domain%qrain,U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
        if (error/=0) then
            print*, "qr", error
            if (error>0) then
                stop "MPDATA Error"
            endif
        endif

        error=0
!         print*, "qs"
        call advect3d(domain%qsnow,U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
        if (error/=0) then
            print*, "qs", error
            if (error>0) then
                stop "MPDATA Error"
            endif
        endif

        error=0
!         print*, "th"
        call advect3d(domain%th,   U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
        if (error/=0) then
            print*, "th", error
            if (error>0) then
                stop "MPDATA Error"
            endif
        endif
        if (options%physics%microphysics==kMP_THOMPSON) then
            error=0
!             print*, "qi"
            call advect3d(domain%ice,  U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
            if (error/=0) then
                print*, "qi", error
                if (error>0) then
                    stop "MPDATA Error"
                endif
            endif

            error=0
!             print*, "qg"
            call advect3d(domain%qgrau,U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
            if (error/=0) then
                print*, "qg", error
                if (error>0) then
                    stop "MPDATA Error"
                endif
            endif

            error=0
!             print*, "ni"
            call advect3d(domain%nice, U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
            if ((error/=0).and.(error/=2)) then
                print*, "ni", error
!                 if (error>0) then
!                     stop "MPDATA Error"
!                 endif
            endif

            error=0
!             print*, "nr"
            call advect3d(domain%nrain,U_m,V_m,W_m,domain%rho,domain%dz,nx,nz,ny,options, error)
            if ((error/=0).and.(error/=2)) then
                print*, "nr", error
!                 if (error>0) then
!                     stop "MPDATA Error"
!                 endif
            endif
        endif
        order=mod(order+1,3)
        
!         call write_domain(domain,options,timestep,"mpdata_test"//trim(str(timestep))//".nc")
        timestep=timestep+1
    end subroutine mpdata
end module adv_mpdata
